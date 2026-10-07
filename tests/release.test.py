import importlib.util, pathlib, unittest
root=pathlib.Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location('release_gate',root/'scripts/check_store_release.py')
gate=importlib.util.module_from_spec(spec);spec.loader.exec_module(gate)
class ReleaseGateTests(unittest.TestCase):
    def valid(self):
        return dict.fromkeys(gate.REQUIRED,True)|{'operator_name':'Test Operator','support_email':'test@example.com','support_url':'https://example.com/support','privacy_policy_url':'https://example.com/privacy','terms_url':'https://example.com/terms','business_model':'free_with_nonconsumable_ad_removal','base_app_price':'free','ad_removal_price_jpy':980,'ad_removal_product_id':'jp.livetalk.mobile.remove_ads','admob_application_id':'ca-app-pub-1234567890123456~1234567890','admob_banner_id':'ca-app-pub-1234567890123456/1234567890'}
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
    def test_official_test_ads_cannot_enter_store_build(self):
        v=self.valid();v['admob_banner_id']='ca-app-pub-3940256099942544/2435281174';self.assertIn('admob_banner_id',gate.blockers(v))
    def test_checklist_cannot_enable_the_preview_connection(self):
        self.assertIn('commercial_connection_adapter_missing',gate.blockers(self.valid()))
    def test_revenue_activation_requires_publisher_verification(self):
        v=self.valid();v['status']='revenue_enabled';self.assertIn('app_ads_txt_verified',gate.blockers(v));self.assertIn('admob_app_readiness_approved',gate.blockers(v))
    def test_purchase_readiness_does_not_implicitly_enable_revenue_ads(self):
        v=self.valid();v.update(admob_app_readiness_approved=True,app_ads_txt_verified=True)
        for status in ['preparation_only','submission_ready',None]:
            v['status']=status;self.assertFalse(gate.revenue_ads_enabled(v))
        v['status']='revenue_enabled';self.assertTrue(gate.revenue_ads_enabled(v))
    def test_revenue_ad_checks_require_verified_booleans(self):
        v=self.valid();v.update(status='revenue_enabled',admob_app_readiness_approved=True,app_ads_txt_verified=True)
        for key in ['admob_app_readiness_approved','app_ads_txt_verified','ad_consent_messages_published','ad_privacy_and_lifecycle_tested','admob_account_and_terms_complete']:
            for missing in [False,'true',None]:
                current=dict(v);current[key]=missing
                self.assertFalse(gate.revenue_ads_enabled(current),key)
    def test_user_business_model_and_price_are_not_silently_changed(self):
        v=self.valid();v['ad_removal_price_jpy']=990;v['business_model']='subscription';self.assertIn('ad_removal_price_jpy',gate.blockers(v));self.assertIn('business_model',gate.blockers(v))
if __name__=='__main__':unittest.main()
