import importlib.util, pathlib, unittest
root=pathlib.Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location('release_gate',root/'scripts/check_store_release.py')
gate=importlib.util.module_from_spec(spec);spec.loader.exec_module(gate)
class ReleaseGateTests(unittest.TestCase):
    def valid(self):
        return dict.fromkeys(gate.REQUIRED,True)|{'operator_name':'Test Operator','support_url':'https://example.com/support','privacy_policy_url':'https://example.com/privacy','terms_url':'https://example.com/terms'}
    def test_checklist_cannot_claim_unimplemented_commercial_adapter(self):
        self.assertIn('commercial_connection_evidence_missing',gate.blockers(self.valid()))
    def test_missing_operator_blocks_release(self):
        v=self.valid();v['operator_name']='';self.assertIn('operator_name',gate.blockers(v))
    def test_non_https_and_credential_urls_are_rejected(self):
        v=self.valid();v['privacy_policy_url']='http://example.com';v['support_url']='https://user:password@example.com';self.assertIn('privacy_policy_url',gate.blockers(v));self.assertIn('support_url',gate.blockers(v))
    def test_carplay_claim_requires_approval_and_tests(self):
        v=self.valid();v['carplay_marketed']=True;self.assertIn('carplay_entitlement_approved',gate.blockers(v));self.assertIn('carplay_vehicle_tests_complete',gate.blockers(v))
    def test_strings_cannot_approve_permissions(self):
        v=self.valid();v['commercial_openai_permission_verified']='true';self.assertIn('commercial_openai_permission_verified',gate.blockers(v))
if __name__=='__main__':unittest.main()
