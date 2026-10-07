"""Release provenance/privacy tests. Header-only fixtures are never executable apps."""
import importlib.util, pathlib, plistlib, struct, subprocess, sys, tempfile, unittest, zipfile

root = pathlib.Path(__file__).resolve().parents[1]
sys.path.insert(0, str(root / 'scripts'))
spec = importlib.util.spec_from_file_location('release_package', root/'scripts/package_release.py')
module = importlib.util.module_from_spec(spec); spec.loader.exec_module(module)

class ReleasePackagingTests(unittest.TestCase):
    def fixture(self, path, changes=None):
        files = {name: subprocess.check_output(['git','show','HEAD:'+name],cwd=root)
                 for name in subprocess.check_output(['git','ls-files','shared/'],cwd=root).decode().splitlines()}
        files.update({'Info.plist': plistlib.dumps({'CFBundleExecutable':'LiveTalk',
            'DTPlatformName':'iphoneos', 'DTSDKName':'iphoneos26.2',
            'CFBundleShortVersionString':'2.5','CFBundleVersion':'25','LTCommerceEnabled':False}),
            'LiveTalk': b'\xcf\xfa\xed\xfe' + struct.pack('<IIIIIII', 0x0100000C,0,2,0,0,0,0),
            'voice/model.vvm':b'fixture','voice/NOTICE.txt':b'fixture',
            'voice/dictionary/sys.dic':b'fixture','PrivacyInfo.xcprivacy':b'fixture'})
        files.update(changes or {})
        with zipfile.ZipFile(path,'w') as archive:
            for name, data in files.items(): archive.writestr('Payload/LiveTalk.app/'+name,data)

    def test_current_shared_runtime_is_accepted(self):
        with tempfile.TemporaryDirectory() as folder:
            path=pathlib.Path(folder)/'fixture.ipa'; self.fixture(path)
            self.assertEqual(module.validate_ipa(path)['version'],'2.5')

    def test_stale_privacy_or_code_cannot_be_packaged_with_new_sources(self):
        for name in ('shared/privacy.txt','shared/app.js'):
            with self.subTest(name=name), tempfile.TemporaryDirectory() as folder:
                path=pathlib.Path(folder)/'fixture.ipa'; self.fixture(path,{name:b'old content'})
                with self.assertRaisesRegex(ValueError,'frozen shared source'): module.validate_ipa(path)

    def test_personal_profile_or_local_storekit_file_cannot_be_redistributed(self):
        for name in ('embedded.mobileprovision','AdRemoval.storekit'):
            with self.subTest(name=name), tempfile.TemporaryDirectory() as folder:
                path=pathlib.Path(folder)/'fixture.ipa'; self.fixture(path,{name:b'private fixture'})
                with self.assertRaises(ValueError): module.validate_ipa(path)

if __name__ == '__main__': unittest.main()
