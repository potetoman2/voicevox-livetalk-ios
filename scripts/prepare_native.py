"""Fetch pinned official mobile libraries and prepare reproducible native projects.

Python 3.12+. Downloads are never executed. The resulting app runs without a PC.
"""
from __future__ import annotations
import argparse
import hashlib
import json
import os
import plistlib
import re
import shutil
import sys
import tarfile
import urllib.parse
import urllib.request
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CORE_VERSION = "0.17.0"
ORT_VERSION = "1.23.2"
MODEL_VERSION = "0.16.4"  # Stable v1 VVM; Nemo avoids individual character voice conditions.
DEFAULT_MODEL = "n0.vvm"
NEMO_SHA256 = "e91e2e6ed5cfa6940ff55b61234ba89c631fce3d0146c23685552e7f5d2fe437"
def long_path(path: Path) -> Path:
    return Path('\\\\?\\' + str(path.resolve())) if os.name == 'nt' else path

VENDOR = long_path(ROOT / "vendor")
RECORDS: dict[str, dict] = {}

def get(url: str, destination: Path, digest: str | None = None) -> Path:
    destination.parent.mkdir(parents=True, exist_ok=True)
    if not destination.exists():
        print("Download:", url, flush=True)
        temp = destination.with_suffix(destination.suffix + ".part")
        headers = {"User-Agent": "LiveTalkMobile-build/1.0"}
        # The workflow's short-lived token is sent only to the official GitHub API.
        if urllib.parse.urlsplit(url).hostname == "api.github.com" and os.environ.get("GITHUB_TOKEN"):
            headers["Authorization"] = "Bearer " + os.environ["GITHUB_TOKEN"]
        request = urllib.request.Request(url, headers=headers)
        try:
            with urllib.request.urlopen(request, timeout=60) as response, temp.open("wb") as out:
                shutil.copyfileobj(response, out)
            temp.replace(destination)
        finally:
            temp.unlink(missing_ok=True)
    sha = hashlib.sha256(destination.read_bytes()).hexdigest()
    if digest and digest.startswith("sha256:") and digest[7:] != sha:
        raise ValueError(f"Release checksum mismatch: {destination.name}")
    RECORDS[destination.name] = {"url": url, "sha256": sha, "bytes": destination.stat().st_size}
    return destination

def release(repo: str, tag: str) -> dict:
    path = get(f"https://api.github.com/repos/VOICEVOX/{repo}/releases/tags/{tag}", VENDOR / "cache" / f"{repo}-{tag}.json")
    return json.loads(path.read_text(encoding="utf-8"))

def asset(info: dict, pattern: str) -> Path:
    matches = [a for a in info["assets"] if re.fullmatch(pattern, a["name"])]
    if len(matches) != 1:
        raise ValueError(f"Expected one official asset matching {pattern}; found {[a['name'] for a in matches]}")
    a = matches[0]
    return get(a["browser_download_url"], VENDOR / "cache" / a["name"], a.get("digest"))

def safe_target(root: Path, name: str) -> Path:
    target = (root / name).resolve()
    if not target.is_relative_to(root.resolve()):
        raise ValueError("Archive path leaves its destination")
    return target

def extract(path: Path) -> Path:
    folder = VENDOR / "unpacked" / path.name
    folder.mkdir(parents=True, exist_ok=True)
    if zipfile.is_zipfile(path):
        with zipfile.ZipFile(path) as archive:
            if sum(i.file_size for i in archive.infolist()) > 2_000_000_000:
                raise ValueError("Archive exceeds allowed size")
            links = []
            for item in archive.infolist():
                safe_target(folder, item.filename)
                if (item.external_attr >> 16) & 0o170000 == 0o120000:
                    destination = safe_target(folder, item.filename)
                    target = (destination.parent / archive.read(item).decode('utf-8')).resolve()
                    if not target.is_relative_to(folder.resolve()): raise ValueError('Archive link leaves its destination')
                    links.append((destination, target))
                else: archive.extract(item, folder)
            # macOS framework aliases are materialized, so Windows needs no symlink privileges.
            for _ in range(12):
                if not links: break
                remaining = []
                for destination, target in links:
                    if not target.exists(): remaining.append((destination, target)); continue
                    destination.parent.mkdir(parents=True, exist_ok=True)
                    if target.is_dir(): shutil.copytree(target, destination, dirs_exist_ok=True)
                    else: shutil.copy2(target, destination)
                if len(remaining) == len(links): raise ValueError('Unresolved archive links')
                links = remaining
            if links: raise ValueError('Too many nested archive links')
    else:
        with tarfile.open(path) as archive:
            for item in archive.getmembers():
                safe_target(folder, item.name)
                if item.islnk() or item.issym():
                    # SONAME symlinks are unnecessary: copy the real library under a stable name.
                    continue
                if not (item.isfile() or item.isdir()):
                    raise ValueError("Special archive entry")
                archive.extract(item, folder, filter="data")
    return folder

def find_one(folder: Path, pattern: str) -> Path:
    found = sorted(folder.rglob(pattern))
    if len(found) != 1:
        raise ValueError(f"Expected one {pattern} under {folder}; found {found}")
    return found[0]

def copy_license_tree(folder: Path, name: str) -> list[str]:
    dest = VENDOR / "licenses" / name
    dest.mkdir(parents=True, exist_ok=True)
    texts = []
    for f in folder.rglob("*"):
        if f.is_file() and (any(word in f.name.lower() for word in ("license", "terms", "copying", "notice", "copyright")) or "利用規約" in f.name):
            relative = f.relative_to(folder)
            out = dest / relative; out.parent.mkdir(parents=True, exist_ok=True); shutil.copy2(f, out)
            try:
                text = f.read_text(encoding="utf-8")
                if len(text) < 100000: texts.append(f"\n--- {name}/{relative} ---\n{text}")
            except UnicodeError:
                pass
    return texts

def voice_inventory(speakers: list, model: Path, selected: str) -> dict:
    result=[]; ids=set()
    for speaker in speakers:
        name=speaker.get('name') if isinstance(speaker,dict) else None
        if not isinstance(name,str) or not name.strip() or len(name)>80 or any(ord(c)<32 for c in name):
            raise ValueError('Invalid voice inventory name')
        styles=speaker.get('styles')
        if not isinstance(styles,list) or not styles: raise ValueError('Missing voice style inventory')
        items=[]
        for style in styles:
            sid=style.get('id') if isinstance(style,dict) else None
            label=style.get('name') if isinstance(style,dict) else None
            if not isinstance(sid,int) or isinstance(sid,bool) or sid<0 or sid in ids:
                raise ValueError('Invalid or duplicate voice style identifier')
            if not isinstance(label,str) or not label.strip() or len(label)>80 or any(ord(c)<32 for c in label):
                raise ValueError('Invalid voice style label')
            ids.add(sid);items.append({'id':sid,'name':label,'type':style.get('type','talk')})
        result.append({'name':name.strip(),'credit':'VOICEVOX Nemo' if selected == DEFAULT_MODEL else 'VOICEVOX:'+name.strip(),'styles':items})
    if not result: raise ValueError('Empty voice inventory')
    return {'schema':1,'model_release':MODEL_VERSION,'asset':selected,
            'voice_family':'nemo' if selected == DEFAULT_MODEL else 'character',
            'model_sha256':hashlib.sha256(model.read_bytes()).hexdigest(),'speakers':result,
            'commercial_rights_reviewed':False}

def prepare_voice(model_name: str | None) -> None:
    voice = VENDOR / "voice"; voice.mkdir(parents=True, exist_ok=True)
    info = release("voicevox_vvm", MODEL_VERSION)
    models = sorted(a["name"] for a in info["assets"] if a["name"].endswith(".vvm"))
    selected = model_name or DEFAULT_MODEL
    if selected not in models: raise ValueError(f"Unknown model. Available: {models}")
    model = asset(info, re.escape(selected))
    if selected == DEFAULT_MODEL and hashlib.sha256(model.read_bytes()).hexdigest() != NEMO_SHA256:
        raise ValueError('Pinned Nemo model checksum mismatch')
    shutil.copy2(model, voice / "model.vvm")
    terms = []
    with zipfile.ZipFile(model) as archive:
        manifest = json.loads(archive.read("manifest.json"))
        speakers = json.loads(archive.read("metas.json"))
        if not isinstance(speakers, list) or not speakers: raise ValueError("Voice credits metadata is missing")
        inventory = voice_inventory(speakers,model,selected)
        names = [speaker.get("name") for speaker in speakers if isinstance(speaker, dict)]
        if len(names) != len(speakers) or any(not isinstance(name, str) or not name.strip() or len(name) > 80 or any(ord(ch) < 32 for ch in name) for name in names): raise ValueError("Invalid voice credits metadata")
        credits = "\n".join(dict.fromkeys(speaker['credit'] for speaker in inventory['speakers']))
        if manifest.get("vvm_format_version") != 1: raise ValueError("Expected pinned v1 model")
        for name in archive.namelist():
            if "license" in name.lower() or "terms" in name.lower() or "利用規約" in name:
                text = archive.read(name).decode("utf-8")
                terms.append(f"\n--- {name} ---\n{text}")
    readme = get(f"https://raw.githubusercontent.com/VOICEVOX/voicevox_vvm/{MODEL_VERSION}/README.md", VENDOR / "cache" / f"vvm-README-{MODEL_VERSION}.md").read_text(encoding="utf-8")
    official_terms = re.search(r'<!-- terms start -->(.*?)<!-- terms end -->', readme, re.S)
    if official_terms: terms.append(official_terms.group(1).strip())
    if selected == DEFAULT_MODEL:
        nemo_terms = ROOT / 'licenses/VOICEVOX_Nemo_TERMS.txt'
        terms.append(nemo_terms.read_text(encoding='utf-8'))
        (VENDOR / 'licenses/voicevox-nemo').mkdir(parents=True, exist_ok=True)
        shutil.copy2(nemo_terms, VENDOR / 'licenses/voicevox-nemo/TERMS.txt')
    if not terms: raise ValueError("Model terms could not be located; do not distribute an app without them")
    dic_archive = get("https://downloads.sourceforge.net/open-jtalk/open_jtalk_dic_utf_8-1.11.tar.gz", VENDOR / "cache" / "open_jtalk_dic_utf_8-1.11.tar.gz")
    dic = find_one(extract(dic_archive), "sys.dic").parent
    shutil.copytree(dic, voice / "dictionary", dirs_exist_ok=True)
    terms += copy_license_tree(dic, "open-jtalk-dictionary")
    notice = "VOICEVOXを使用しています。\n音声を公開する際はVOICEVOXと各音声の利用条件・クレジット表記に従ってください。\nhttps://voicevox.hiroshiba.jp/term/\n\n読み込みモデル: " + selected + "\n\n同梱音声のクレジット:\n" + credits + "\n\n" + "\n".join(terms)
    (voice / "NOTICE.txt").write_text(notice, encoding="utf-8")
    inventory['notice_sha256']=hashlib.sha256((voice/'NOTICE.txt').read_bytes()).hexdigest()
    (voice/'inventory.json').write_text(json.dumps(inventory,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')

def prepare_android(core: dict, ort: dict) -> None:
    dest = ROOT / "android/app/src/main"
    for abi, core_arch, ort_arch in [("arm64-v8a", "arm64", "arm64"), ("x86_64", "x86_64", "x64")]:
        c = extract(asset(core, rf"voicevox_core-android-{core_arch}-{re.escape(CORE_VERSION)}\.zip"))
        r = extract(asset(ort, rf"voicevox_onnxruntime-android-{ort_arch}-{re.escape(ORT_VERSION)}\.tgz"))
        out = dest / "jniLibs" / abi; out.mkdir(parents=True, exist_ok=True)
        shutil.copy2(find_one(c, "libvoicevox_core.so"), out / "libvoicevox_core.so")
        runtimes = [f for f in r.rglob("libvoicevox_onnxruntime.so*") if f.is_file()]
        if not runtimes: raise ValueError("Official VOICEVOX ONNX Runtime missing")
        shutil.copy2(max(runtimes, key=lambda f: f.stat().st_size), out / "libvoicevox_onnxruntime.so")
        (VENDOR / "include").mkdir(parents=True, exist_ok=True)
        shutil.copy2(find_one(c, "voicevox_core.h"), VENDOR / "include/voicevox_core.h")
        copy_license_tree(c, "voicevox-core"); copy_license_tree(r, "voicevox-onnxruntime")
    shutil.copytree(VENDOR / "voice", dest / "assets/voice", dirs_exist_ok=True)
    shutil.copytree(VENDOR / "licenses", dest / "assets/voice/licenses", dirs_exist_ok=True)
    (dest / "assets/voice/NOTICE.txt").write_text((VENDOR / "voice/NOTICE.txt").read_text(encoding="utf-8") + "\n\nVOICEVOX ONNX Runtime / CORE のライセンスは voice/licenses に同梱。", encoding="utf-8")

def normalize_framework_identifiers(folder: Path) -> list[dict]:
    changes = []
    for path in folder.rglob('Info.plist'):
        if path.parent.suffix != '.framework': continue
        info = plistlib.loads(path.read_bytes())
        old = info.get('CFBundleIdentifier', '')
        new = old.replace('_', '-')
        if not re.fullmatch(r'[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+', new):
            raise ValueError('Invalid framework bundle identifier: '+path.parent.name)
        if old != new:
            info['CFBundleIdentifier'] = new
            path.write_bytes(plistlib.dumps(info))
            changes.append({'framework':str(path.relative_to(folder)), 'original':old, 'normalized':new})
    return changes

def prepare_ios(core: dict, ort: dict) -> None:
    c = extract(asset(core, rf"voicevox_core-xcframework-{re.escape(CORE_VERSION)}\.zip"))
    r = extract(asset(ort, rf"voicevox_onnxruntime-ios-xcframework-{re.escape(ORT_VERSION)}\.zip"))
    out = VENDOR / "ios"; out.mkdir(parents=True, exist_ok=True)
    dependencies = []
    for folder in (c, r):
        for framework in folder.rglob("*.xcframework"):
            shutil.copytree(framework, out / framework.name, dirs_exist_ok=True)
            dependencies.append(f"      - framework: ../vendor/ios/{framework.name}\n        embed: true\n        codeSign: true")
    if len(dependencies) != 2: raise ValueError("Expected core and ONNX Runtime XCFrameworks")
    # Xcode 26 rejects underscores in the vendor's framework bundle identifier.
    # Adjust copied wrapper metadata only; preserve the downloaded archive and executable.
    changes = normalize_framework_identifiers(out)
    (out/'bundle-identifier-adjustments.json').write_text(json.dumps(changes,indent=2)+'\n',encoding='utf-8')
    # Use the platform-neutral source header, rather than the Android header with its load-only macro.
    (VENDOR / "include").mkdir(parents=True, exist_ok=True)
    get(f"https://raw.githubusercontent.com/VOICEVOX/voicevox_core/{CORE_VERSION}/crates/voicevox_core_c_api/include/voicevox_core.h", VENDOR / "cache/voicevox_core.h")
    shutil.copy2(VENDOR / "cache/voicevox_core.h", VENDOR / "include/voicevox_core.h")
    copy_license_tree(c, "voicevox-core"); copy_license_tree(r, "voicevox-onnxruntime")
    # Official XCFramework archives contain no license files; include pinned source notices.
    for name, url in {
        "voicevox-core/LICENSE": f"https://raw.githubusercontent.com/VOICEVOX/voicevox_core/{CORE_VERSION}/LICENSE",
        "voicevox-onnxruntime/LICENSE-builder": f"https://raw.githubusercontent.com/VOICEVOX/onnxruntime-builder/voicevox_onnxruntime-{ORT_VERSION}/LICENSE",
        "voicevox-onnxruntime/LICENSE-runtime": f"https://raw.githubusercontent.com/microsoft/onnxruntime/v{ORT_VERSION}/LICENSE",
        "voicevox-onnxruntime/ThirdPartyNotices.txt": f"https://raw.githubusercontent.com/microsoft/onnxruntime/v{ORT_VERSION}/ThirdPartyNotices.txt",
    }.items():
        get(url, VENDOR / "licenses" / name)
    shutil.copytree(VENDOR / "licenses", VENDOR / "voice/licenses", dirs_exist_ok=True)
    template = (ROOT / "ios/project.template.yml").read_text(encoding="utf-8")
    template = template.replace("      # PREPARE_NATIVE inserts the downloaded XCFramework dependency here.", "\n".join(dependencies))
    (ROOT / "ios/project.yml").write_text(template, encoding="utf-8")

def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("target", choices=["android", "ios", "all"])
    parser.add_argument("--model", help="Official VVM asset filename; default is the pinned VOICEVOX Nemo n0.vvm")
    args = parser.parse_args()
    if sys.version_info < (3, 12): raise SystemExit("Python 3.12 or newer is required")
    core = release("voicevox_core", CORE_VERSION)
    ort = release("onnxruntime-builder", "voicevox_onnxruntime-" + ORT_VERSION)
    prepare_voice(args.model)
    if args.target in ("android", "all"): prepare_android(core, ort)
    if args.target in ("ios", "all"): prepare_ios(core, ort)
    (VENDOR / "download-manifest.json").write_text(json.dumps(RECORDS, ensure_ascii=False, indent=2), encoding="utf-8")
    print("Native assets prepared. No credentials or account data are bundled.")

if __name__ == "__main__":
    try: main()
    except Exception as error: raise SystemExit(f"Preparation failed: {error}. Check the network and rerun; completed downloads remain cached.")
