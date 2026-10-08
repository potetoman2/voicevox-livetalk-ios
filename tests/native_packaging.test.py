import importlib.util, plistlib, tempfile, unittest
from pathlib import Path
spec = importlib.util.spec_from_file_location('prepare_native',Path(__file__).parents[1]/'scripts/prepare_native.py')
module = importlib.util.module_from_spec(spec);spec.loader.exec_module(module)

class FrameworkMetadataTests(unittest.TestCase):
    def test_nemo_inventory_uses_common_credit_for_all_nine_voices(self):
        with tempfile.TemporaryDirectory() as directory:
            model=Path(directory)/'n0.vvm';model.write_bytes(b'fixture, not a voice model')
            speakers=[{'name':f'Neutral {i}','styles':[{'id':10000+i,'name':'Normal'}]} for i in range(9)]
            inventory=module.voice_inventory(speakers,model,'n0.vvm')
            self.assertEqual(inventory['voice_family'],'nemo')
            self.assertEqual(inventory['model_release'],'0.16.4')
            self.assertEqual({s['credit'] for s in inventory['speakers']},{'VOICEVOX Nemo'})
            self.assertEqual(len(inventory['speakers']),9)
            self.assertEqual(module.DEFAULT_MODEL,'n0.vvm')
    def test_inventory_covers_every_embedded_speaker_and_style(self):
        with tempfile.TemporaryDirectory() as directory:
            model=Path(directory)/'0.vvm';model.write_bytes(b'test fixture, not a model')
            inventory=module.voice_inventory([{'name':'Voice A','styles':[{'id':1,'name':'Normal'}]},
                                             {'name':'Voice B','styles':[{'id':2,'name':'Quiet'}]}],model,'0.vvm')
            self.assertEqual([s['credit'] for s in inventory['speakers']],['VOICEVOX:Voice A','VOICEVOX:Voice B'])
            self.assertEqual([s['styles'][0]['id'] for s in inventory['speakers']],[1,2])
            self.assertEqual(len(inventory['model_sha256']),64)
            self.assertFalse(inventory['commercial_rights_reviewed'])
    def test_ambiguous_model_metadata_stops_packaging(self):
        with tempfile.TemporaryDirectory() as directory:
            model=Path(directory)/'model.vvm';model.write_bytes(b'fixture')
            for speakers in ([],[{'name':'Voice','styles':[]}],
                    [{'name':'Voice','styles':[{'id':True,'name':'Normal'}]}],
                    [{'name':'Voice','styles':[{'id':1,'name':'Normal'},{'id':1,'name':'Duplicate'}]}]):
                with self.subTest(speakers=speakers),self.assertRaises(ValueError):
                    module.voice_inventory(speakers,model,'model.vvm')
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
