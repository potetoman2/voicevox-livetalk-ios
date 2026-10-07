import hashlib, importlib.util, json, pathlib, tempfile, unittest
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
    def test_current_store_cannot_sell_by_flipping_plist_switches(self):
        self.assertIn('commercial_connection_adapter_unwired',gate.blockers(self.valid()))
    def test_empty_adapter_and_empty_evidence_are_not_approval(self):
        with tempfile.TemporaryDirectory() as folder:
            root=pathlib.Path(folder);(root/'release').mkdir();(root/'ios/LiveTalk').mkdir(parents=True)
            (root/'release/commercial-connection-verification.json').write_text('{}')
            (root/'ios/LiveTalk/CommercialChatGPTConnection.swift').write_text('// TODO')
            result=gate.blockers(self.valid(),root)
            self.assertIn('commercial_connection_evidence_missing',result)
            self.assertIn('commercial_connection_adapter_missing',result)
            self.assertIn('commercial_connection_adapter_unwired',result)
    def make_evidence(self,root,key):
        (root/'docs/evidence').mkdir(parents=True);(root/'release').mkdir()
        body=b'A sanitized review summary with a scope, result and a reference to a privately held verification record.\n'
        (root/'docs/evidence/summary.txt').write_bytes(body)
        item={'status':'verified','reviewed_by':'Test fixture','reviewed_on':'2026-10-07',
              'reference':'TEST ONLY','summary_path':'docs/evidence/summary.txt',
              'sha256':hashlib.sha256(body).hexdigest(),'runtime_sha256':gate.source_fingerprint(root)}
        if key=='source_license_decided':
            (root/'LICENSE.txt').write_bytes(b'TEST-ONLY RIGHTS NOTICE')
            item['license_sha256']=hashlib.sha256((root/'LICENSE.txt').read_bytes()).hexdigest()
        index={'schema':1,'items':{key:item}}
        (root/'release/evidence-index.json').write_text(json.dumps(index))
        return index
    def test_hash_and_runtime_drift_invalidate_technical_evidence(self):
        with tempfile.TemporaryDirectory() as folder:
            root=pathlib.Path(folder);key='security_review_complete'
            self.make_evidence(root,key);self.assertTrue(gate.evidence_valid(key,root))
            (root/'shared').mkdir();(root/'shared/app.js').write_text('changed runtime')
            self.assertFalse(gate.evidence_valid(key,root))
        with tempfile.TemporaryDirectory() as folder:
            root=pathlib.Path(folder);key='source_license_decided'
            self.make_evidence(root,key);(root/'docs/evidence/summary.txt').write_text('changed')
            self.assertFalse(gate.evidence_valid(key,root))
    def test_evidence_cannot_read_outside_the_approved_summary_folder(self):
        for unsafe in ('../private.txt','docs/evidence/../../../private.txt','C:/private.txt','/private.txt'):
            with self.subTest(path=unsafe), tempfile.TemporaryDirectory() as folder:
                root=pathlib.Path(folder);key='source_license_decided';index=self.make_evidence(root,key)
                index['items'][key]['summary_path']=unsafe
                (root/'release/evidence-index.json').write_text(json.dumps(index))
                self.assertFalse(gate.evidence_valid(key,root))
    def test_a_checkmark_without_a_review_record_cannot_pass(self):
        self.assertIn('paid_apps_agreement_complete_evidence_invalid',gate.blockers(self.valid()))
    def test_malformed_config_reports_blockers_and_never_passes(self):
        self.assertEqual(gate.blockers([]),['readiness_schema_invalid'])
        v=self.valid();v.update(support_email=None,support_url='https://[invalid',terms_url=True,admob_banner_id=False)
        for key in ('support_email','support_url','terms_url','admob_banner_id'):
            self.assertIn(key,gate.blockers(v))
    def test_a_changed_license_requires_a_new_owner_decision_record(self):
        with tempfile.TemporaryDirectory() as folder:
            root=pathlib.Path(folder);key='source_license_decided';self.make_evidence(root,key)
            self.assertTrue(gate.evidence_valid(key,root))
            (root/'LICENSE.txt').write_text('CHANGED RIGHTS')
            self.assertFalse(gate.evidence_valid(key,root))
    def test_a_different_embedded_voice_model_cannot_reuse_the_old_rights_review(self):
        with tempfile.TemporaryDirectory() as folder:
            root=pathlib.Path(folder);key='voice_rights_review_complete';index=self.make_evidence(root,key)
            voice=root/'vendor/voice';voice.mkdir(parents=True)
            (voice/'model.vvm').write_bytes(b'TEST MODEL');(voice/'NOTICE.txt').write_bytes(b'TEST NOTICE')
            inventory={'schema':1,'speakers':[{'name':'TEST ONLY'}],
                       'model_sha256':hashlib.sha256((voice/'model.vvm').read_bytes()).hexdigest(),
                       'notice_sha256':hashlib.sha256((voice/'NOTICE.txt').read_bytes()).hexdigest()}
            (voice/'inventory.json').write_text(json.dumps(inventory))
            index['items'][key].update(inventory_sha256=hashlib.sha256((voice/'inventory.json').read_bytes()).hexdigest(),
                                      model_sha256=inventory['model_sha256'],notice_sha256=inventory['notice_sha256'])
            (root/'release/evidence-index.json').write_text(json.dumps(index))
            self.assertEqual(gate.voice_assets_blockers(root),[])
            (voice/'model.vvm').write_bytes(b'ANOTHER MODEL')
            self.assertIn('voice_assets_differ_from_review',gate.voice_assets_blockers(root))
if __name__=='__main__':unittest.main()
