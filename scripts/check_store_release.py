"""Reject accidental store builds until evidenced publication requirements are complete."""
import argparse, json, re
from pathlib import Path
from urllib.parse import urlsplit

ROOT = Path(__file__).resolve().parents[1]
REQUIRED = ['apple_developer_program_active', 'paid_apps_agreement_complete', 'bank_and_tax_details_complete',
 'commercial_openai_permission_verified', 'commercial_connection_implemented_and_tested',
 'voice_rights_review_complete', 'source_license_decided', 'privacy_label_review_complete',
 'security_review_complete', 'purchase_flow_tested', 'real_device_release_tests_complete',
 'admob_account_and_terms_complete', 'ad_consent_messages_published', 'ad_privacy_and_lifecycle_tested',
 'ad_removal_product_registered']
def revenue_ads_enabled(value):
    return value.get('status') == 'revenue_enabled' and all(value.get(key) is True
        for key in ['admob_account_and_terms_complete', 'ad_consent_messages_published',
                    'ad_privacy_and_lifecycle_tested', 'admob_app_readiness_approved', 'app_ads_txt_verified'])

def blockers(value):
    failed = [key for key in REQUIRED if value.get(key) is not True]
    if not isinstance(value.get('operator_name'), str) or not value['operator_name'].strip(): failed.append('operator_name')
    if value.get('business_model') != 'free_with_nonconsumable_ad_removal' or value.get('base_app_price') != 'free': failed.append('business_model')
    if value.get('ad_removal_price_jpy') != 980 or isinstance(value.get('ad_removal_price_jpy'), bool): failed.append('ad_removal_price_jpy')
    if value.get('ad_removal_product_id') != 'jp.livetalk.mobile.remove_ads': failed.append('ad_removal_product_id')
    if not re.fullmatch(r'[^\s@]+@[^\s@]+\.[^\s@]+', value.get('support_email', '')): failed.append('support_email')
    for key, separator in [('admob_application_id', '~'), ('admob_banner_id', '/')]:
        v=value.get(key, '')
        if not re.fullmatch(r'ca-app-pub-[0-9]{16}'+re.escape(separator)+r'[0-9]{10}', v) or v.startswith('ca-app-pub-3940256099942544'):
            failed.append(key)
    for key in ['support_url', 'privacy_policy_url', 'terms_url']:
        u = urlsplit(value.get(key, ''))
        if u.scheme != 'https' or not u.hostname or u.username or u.password: failed.append(key)
    if value.get('carplay_marketed'):
        failed.extend(key for key in ['carplay_entitlement_approved', 'carplay_vehicle_tests_complete'] if value.get(key) is not True)
    # There is currently no approved paid connection adapter; a checklist cannot enable one.
    info = ROOT / 'release/commercial-connection-verification.json'
    if not info.exists(): failed.append('commercial_connection_evidence_missing')
    if not (ROOT/'ios/LiveTalk/CommercialChatGPTConnection.swift').exists(): failed.append('commercial_connection_adapter_missing')
    # Publisher verification can depend on the first store listing; it gates revenue activation.
    if value.get('status') == 'revenue_enabled':
        failed.extend(key for key in ['admob_app_readiness_approved','app_ads_txt_verified'] if value.get(key) is not True)
    return failed
if __name__ == '__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--report',type=Path);args=parser.parse_args()
    value=json.loads((ROOT/'release/store-readiness.json').read_text(encoding='utf-8')); failed=blockers(value)
    result={'ready':not failed,'blockers':failed,'checklist_is_not_legal_or_security_approval':True}
    if args.report: args.report.parent.mkdir(parents=True,exist_ok=True);args.report.write_text(json.dumps(result,indent=2)+'\n')
    print(json.dumps(result,ensure_ascii=False,indent=2))
    raise SystemExit(1 if failed else 0)
