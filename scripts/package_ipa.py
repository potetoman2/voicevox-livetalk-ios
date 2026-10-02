"""Package a compiled arm64 iPhone app. Never disguise source files as an IPA."""
from __future__ import annotations
import argparse
import hashlib
import json
import os
import plistlib
import stat
import struct
import zipfile
from pathlib import Path

ARM64 = 0x0100000C

def arm64_executable(data: bytes) -> bool:
    if len(data) < 32:
        return False
    if data[:4] == b'\xcf\xfa\xed\xfe':
        cpu, _, filetype = struct.unpack_from('<III', data, 4)
        return cpu == ARM64 and filetype == 2
    if data[:4] in (b'\xca\xfe\xba\xbe', b'\xca\xfe\xba\xbf'):
        count = struct.unpack_from('>I', data, 4)[0]
        if count > 32:
            return False
        wide = data[:4] == b'\xca\xfe\xba\xbf'
        size = 32 if wide else 20
        for i in range(count):
            start = 8 + size * i
            if start + size > len(data):
                return False
            cpu = struct.unpack_from('>I', data, start)[0]
            offset, length = struct.unpack_from('>QQ' if wide else '>II', data, start + 8)
            if cpu == ARM64 and offset + length <= len(data) and arm64_executable(data[offset:offset+length]):
                return True
    return False

def validate_app(app: Path) -> dict:
    if not app.is_dir() or app.suffix != '.app':
        raise ValueError('Provide a compiled .app directory, not a source directory')
    info = plistlib.loads((app / 'Info.plist').read_bytes())
    if info.get('DTPlatformName') != 'iphoneos' or 'iPhoneOS' not in info.get('CFBundleSupportedPlatforms', []):
        raise ValueError('Only an iPhone device build can be packaged; simulator builds are not installable')
    executable = info.get('CFBundleExecutable', '')
    if not executable or Path(executable).name != executable or '$' in executable:
        raise ValueError('Invalid executable name')
    if not arm64_executable((app / executable).read_bytes()):
        raise ValueError('The app lacks a compiled arm64 Mach-O executable')
    for name in ['shared/index.html', 'shared/app.js', 'voice/model.vvm', 'voice/NOTICE.txt', 'voice/dictionary/sys.dic',
                 'Frameworks/voicevox_core.framework', 'Frameworks/voicevox_onnxruntime.framework']:
        if not (app / name).exists():
            raise ValueError(f'Missing runtime content: {name}')
    for path in app.rglob('*'):
        if path.is_symlink() and not path.resolve().is_relative_to(app.resolve()):
            raise ValueError(f'App symlink leaves the bundle: {path}')
    if (app / 'embedded.mobileprovision').exists() or (app / '_CodeSignature').exists():
        raise ValueError('Expected an unsigned app without an embedded signing profile')
    return info

def package_app(app: Path, destination: Path) -> dict:
    info = validate_app(app)
    destination.parent.mkdir(parents=True, exist_ok=True)
    temp = destination.with_suffix('.ipa.part')
    prefix = 'Payload/' + app.name + '/'
    try:
        with zipfile.ZipFile(temp, 'w', zipfile.ZIP_DEFLATED, compresslevel=6) as z:
            for path in sorted(app.rglob('*')):
                name = prefix + path.relative_to(app).as_posix()
                if path.is_symlink():
                    entry = zipfile.ZipInfo(name)
                    entry.create_system = 3
                    entry.external_attr = (stat.S_IFLNK | 0o777) << 16
                    z.writestr(entry, os.readlink(path).encode('utf-8'))
                elif path.is_file():
                    z.write(path, name)
        with zipfile.ZipFile(temp) as z:
            if z.testzip() is not None:
                raise ValueError('IPA CRC verification failed')
            if z.read(prefix + info['CFBundleExecutable']) != (app / info['CFBundleExecutable']).read_bytes():
                raise ValueError('IPA executable verification failed')
        temp.replace(destination)
    finally:
        temp.unlink(missing_ok=True)
    with destination.open('rb') as source:
        digest = hashlib.file_digest(source, 'sha256').hexdigest()
    destination.with_suffix('.ipa.sha256').write_text(digest + '  ' + destination.name + '\n', encoding='utf-8')
    report = {'bundle_id': info.get('CFBundleIdentifier'), 'platform': 'iphoneos', 'architecture': 'arm64',
              'signed': False, 'requires_device_signing': True, 'bytes': destination.stat().st_size, 'sha256': digest,
              'validation': 'Package structure and compiled executable only; real-device behavior must be tested'}
    (destination.parent / 'ipa-report.json').write_text(json.dumps(report, indent=2), encoding='utf-8')
    return report

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('app', type=Path)
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    print(json.dumps(package_app(args.app, args.output), indent=2))
