import importlib.util, plistlib, tempfile, unittest
from pathlib import Path
spec = importlib.util.spec_from_file_location('prepare_native',Path(__file__).parents[1]/'scripts/prepare_native.py')
module = importlib.util.module_from_spec(spec);spec.loader.exec_module(module)

class FrameworkMetadataTests(unittest.TestCase):
    def test_normalizes_vendor_identifier_without_changing_binary_or_executable_name(self):
        with tempfile.TemporaryDirectory() as directory:
            folder=Path(directory);framework=folder/'ios-arm64'/'voicevox_onnxruntime.framework';framework.mkdir(parents=True)
            binary=framework/'voicevox_onnxruntime';binary.write_bytes(b'UNCHANGED_EXECUTABLE')
            info={'CFBundleIdentifier':'jp.hiroshiba.voicevox.voicevox_onnxruntime','CFBundleExecutable':binary.name,'CFBundleVersion':'1.23.2'}
            (framework/'Info.plist').write_bytes(plistlib.dumps(info))
            changes=module.normalize_framework_identifiers(folder)
            adjusted=plistlib.loads((framework/'Info.plist').read_bytes())
            self.assertEqual(adjusted['CFBundleIdentifier'],'jp.hiroshiba.voicevox.voicevox-onnxruntime')
            self.assertEqual(adjusted['CFBundleExecutable'],binary.name)
            self.assertEqual(binary.read_bytes(),b'UNCHANGED_EXECUTABLE')
            self.assertEqual(len(changes),1)
            self.assertEqual(module.normalize_framework_identifiers(folder),[], 'Repeating preparation should be stable')
    def test_invalid_identifier_is_rejected_instead_of_silently_rewritten(self):
        with tempfile.TemporaryDirectory() as directory:
            folder=Path(directory);framework=folder/'Bad.framework';framework.mkdir()
            (framework/'Info.plist').write_bytes(plistlib.dumps({'CFBundleIdentifier':'../../bad'}))
            with self.assertRaises(ValueError):module.normalize_framework_identifiers(folder)

if __name__=='__main__':unittest.main()
