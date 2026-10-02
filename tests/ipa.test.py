import importlib.util
import plistlib
import struct
import tempfile
import unittest
import zipfile
from pathlib import Path

spec = importlib.util.spec_from_file_location('package_ipa', Path(__file__).parents[1] / 'scripts/package_ipa.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

class IPATests(unittest.TestCase):
    def app(self, directory):
        app = Path(directory) / 'Example.app'; app.mkdir()
        (app / 'Info.plist').write_bytes(plistlib.dumps({'DTPlatformName': 'iphoneos', 'CFBundleSupportedPlatforms': ['iPhoneOS'],
            'CFBundleExecutable': 'Example', 'CFBundleIdentifier': 'jp.livetalk.test',
            'NSMicrophoneUsageDescription': 'Test microphone', 'NSSpeechRecognitionUsageDescription': 'Test speech',
            'UILaunchScreen': {}, 'UIApplicationSceneManifest': {'UIApplicationSupportsMultipleScenes': False}}))
        # A header-only fixture validates the packager, never an app intended to run.
        (app / 'Example').write_bytes(b'\xcf\xfa\xed\xfe' + struct.pack('<IIIIIII', module.ARM64, 0, 2, 0, 0, 0, 0))
        for name in ['shared/index.html', 'shared/app.js', 'voice/model.vvm', 'voice/NOTICE.txt', 'voice/dictionary/sys.dic']:
            p = app / name; p.parent.mkdir(parents=True, exist_ok=True); p.write_text('test', encoding='utf-8')
        for name in ['voicevox_core', 'voicevox_onnxruntime']:
            p = app / 'Frameworks' / (name + '.framework'); p.mkdir(parents=True); (p / name).write_text('test')
        return app

    def test_packaging_checks_crc_and_executable(self):
        with tempfile.TemporaryDirectory() as folder:
            app = self.app(folder); output = Path(folder) / 'unsigned.ipa'
            report = module.package_app(app, output)
            self.assertFalse(report['signed']); self.assertTrue(report['requires_device_signing'])
            with zipfile.ZipFile(output) as z:
                self.assertIsNone(z.testzip()); self.assertEqual(z.read('Payload/Example.app/Example'), (app/'Example').read_bytes())

    def test_source_directory_cannot_be_renamed_to_ipa(self):
        with tempfile.TemporaryDirectory() as folder:
            with self.assertRaises(ValueError): module.validate_app(Path(folder))

    def test_simulator_build_is_rejected(self):
        with tempfile.TemporaryDirectory() as folder:
            app = self.app(folder); info = plistlib.loads((app/'Info.plist').read_bytes()); info['DTPlatformName'] = 'iphonesimulator'
            (app/'Info.plist').write_bytes(plistlib.dumps(info))
            with self.assertRaises(ValueError): module.validate_app(app)

    def test_non_macho_and_missing_model_are_rejected(self):
        with tempfile.TemporaryDirectory() as folder:
            app = self.app(folder); executable = (app/'Example').read_bytes(); (app/'Example').write_text('print("source")')
            with self.assertRaises(ValueError): module.validate_app(app)
            (app/'Example').write_bytes(executable); (app/'voice/model.vvm').unlink()
            with self.assertRaises(ValueError): module.validate_app(app)

    def test_signing_profile_is_not_distributed(self):
        with tempfile.TemporaryDirectory() as folder:
            app = self.app(folder); (app/'embedded.mobileprovision').write_text('test')
            with self.assertRaises(ValueError): module.validate_app(app)

    def test_privacy_descriptions_must_survive_project_generation(self):
        with tempfile.TemporaryDirectory() as folder:
            app = self.app(folder)
            original = plistlib.loads((app/'Info.plist').read_bytes())
            for key in ('NSMicrophoneUsageDescription', 'NSSpeechRecognitionUsageDescription', 'UILaunchScreen', 'UIApplicationSceneManifest'):
                info = dict(original); del info[key]
                (app/'Info.plist').write_bytes(plistlib.dumps(info))
                with self.subTest(key=key), self.assertRaises(ValueError): module.validate_app(app)

if __name__ == '__main__': unittest.main()
