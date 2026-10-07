"""Package the reviewed source and an actual unsigned iPhone IPA."""
import argparse, hashlib, json, plistlib, subprocess, sys, zipfile
from pathlib import Path
from package_ipa import arm64_executable

root = Path(__file__).resolve().parents[1]
def validate_ipa(path):
    with zipfile.ZipFile(path) as archive:
        if archive.testzip() is not None:
            raise ValueError('Corrupt IPA')
        names = archive.namelist()
        info_names = [n for n in names if n.startswith('Payload/') and n.count('/')==2 and n.endswith('/Info.plist')]
        if len(info_names)!=1:
            raise ValueError('Expected one compiled app')
        prefix=info_names[0][:-len('Info.plist')]
        info=plistlib.loads(archive.read(info_names[0]))
        executable=info.get('CFBundleExecutable','')
        if not executable or '/' in executable or not arm64_executable(archive.read(prefix+executable)):
            raise ValueError('Missing arm64 device executable')
        if info.get('DTPlatformName')!='iphoneos' or info.get('CFBundleShortVersionString')!='2.5':
            raise ValueError('Expected the 2.5 iPhone device build')
        if int(str(info.get('DTSDKName','iphoneos0')).replace('iphoneos','').split('.')[0]) < 26:
            raise ValueError('Expected the iOS 26 or newer SDK')
        if info.get('LTCommerceEnabled') is not False:
            raise ValueError('Personal preview must not enable commercial billing')
        if info.get('LTRevenueAdsEnabled') is not False:
            raise ValueError('Personal preview must not enable revenue advertisements')
        for relative in ['shared/app.js','voice/model.vvm','voice/NOTICE.txt','voice/dictionary/sys.dic','PrivacyInfo.xcprivacy']:
            if prefix+relative not in names:
                raise ValueError('Missing runtime content: '+relative)
        if any('_CodeSignature/' in n or n.endswith('embedded.mobileprovision') for n in names):
            raise ValueError('Do not redistribute personal signing information')
        if any(n.endswith('.storekit') or '.xctest/' in n for n in names):
            raise ValueError('Do not distribute local purchase testing resources in the app')
        shared = subprocess.check_output(['git','ls-files','shared/'],cwd=root).decode().splitlines()
        for relative in shared:
            expected = subprocess.check_output(['git','show','HEAD:'+relative],cwd=root)
            if prefix+relative not in names or archive.read(prefix+relative) != expected:
                raise ValueError('IPA does not match frozen shared source: '+relative)
        return {'version':info['CFBundleShortVersionString'],'build':info['CFBundleVersion'],'signed':False,'requires_device_signing':True,'experimental_chat':info.get('LTExperimentalChatEnabled',False)}
def package(destination,ipa=None):
    subprocess.run([sys.executable,str(root/'scripts/verify_source.py')],cwd=root,check=True)
    subprocess.run([sys.executable,str(root/'scripts/security_check.py')],cwd=root,check=True)
    files=subprocess.check_output(['git','ls-files','-z'],cwd=root).decode().split('\0')
    report={'version':'2.5','improvement_cycles':20,'source_commit':subprocess.check_output(['git','rev-parse','HEAD'],cwd=root).decode().strip(),'iphone_runtime_verified':False,'app_store_approved':False,'commercial_openai_permission_verified':False,'purchase_sandbox_verified':False,'production_ads_verified':False}
    if ipa:
        report['ipa']=validate_ipa(ipa)
        report['ipa']['sha256']=hashlib.sha256(ipa.read_bytes()).hexdigest()
    destination=Path(destination).resolve()
    destination.parent.mkdir(parents=True,exist_ok=True)
    with zipfile.ZipFile(destination,'w',zipfile.ZIP_DEFLATED,compresslevel=6) as archive:
        for name in filter(None,files):
            if any(part in ['.git','node_modules','vendor','.env'] for part in Path(name).parts) or Path(name).suffix in ['.p8','.p12','.pfx','.pem','.key','.mobileprovision']:
                raise ValueError('Private or generated content in source list')
            archive.writestr('LiveTalk_v2.5/source/'+name,subprocess.check_output(['git','show','HEAD:'+name],cwd=root))
        if ipa:
            archive.write(ipa,'LiveTalk_v2.5/iPhone/VOICEVOX_LiveTalk_iOS_v2.5_UNSIGNED.ipa')
        archive.writestr('LiveTalk_v2.5/release-report.json',json.dumps(report,ensure_ascii=False,indent=2))
    with zipfile.ZipFile(destination) as archive:
        if archive.testzip() is not None:
            raise ValueError('Release ZIP CRC failed')
    destination.with_suffix('.zip.sha256').write_text(hashlib.sha256(destination.read_bytes()).hexdigest()+'  '+destination.name+'\n')
    print(json.dumps(report,ensure_ascii=False,indent=2))
if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('destination');parser.add_argument('--ipa',type=Path);args=parser.parse_args()
    package(args.destination,args.ipa)
