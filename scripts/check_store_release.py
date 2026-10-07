"""Reject accidental store builds until evidenced publication requirements are complete."""
import argparse, datetime, hashlib, json, re
from pathlib import Path
from urllib.parse import urlsplit

ROOT = Path(__file__).resolve().parents[1]
REQUIRED = ['apple_developer_program_active', 'paid_apps_agreement_complete', 'bank_and_tax_details_complete',
 'commercial_openai_permission_verified', 'commercial_connection_implemented_and_tested',
 'voice_rights_review_complete', 'source_license_decided', 'privacy_label_review_complete',
 'security_review_complete', 'purchase_flow_tested', 'real_device_release_tests_complete',
 'admob_account_and_terms_complete', 'ad_consent_messages_published', 'ad_privacy_and_lifecycle_tested',
 'ad_removal_product_registered', 'consumer_disclosures_review_complete',
 'overseas_data_processing_review_complete', 'final_policies_review_complete',
 'app_review_access_prepared', 'support_and_incident_process_ready',
 'independent_security_review_complete']

def reviewed_bytes(path):
    # Git text checkout line endings vary by OS; binary assets keep their exact bytes.
    data=path.read_bytes()
    return data.replace(b'\r\n',b'\n') if path.suffix in ('.swift','.m','.mm','.h','.js','.txt',
        '.json','.html','.css','.yml','.plist','.xcprivacy','.md') else data

def source_fingerprint(root=ROOT):
    """Bind technical review evidence to the runtime and its dependency preparation."""
    paths = [p for folder in ('ios/LiveTalk', 'shared', 'native') for p in (root/folder).rglob('*')
             if p.is_file() and not p.is_symlink()]
    paths += [root/name for name in ('scripts/prepare_native.py', 'ios/project.template.yml',
                                     'package-lock.json') if (root/name).is_file()]
    digest = hashlib.sha256()
    for path in sorted(paths, key=lambda p:p.relative_to(root).as_posix()):
        digest.update(path.relative_to(root).as_posix().encode()+b'\0')
        digest.update(hashlib.sha256(reviewed_bytes(path)).digest())
    return digest.hexdigest()

def evidence_valid(key, root=ROOT):
    # Evidence is a sanitized, reviewed summary; private contracts stay outside the repo.
    # Hashes detect drift. They do not prove permission, legality, or security themselves.
    try:
        index = json.loads((root/'release/evidence-index.json').read_text(encoding='utf-8'))
        item = index['items'][key]
        if index.get('schema') != 1 or item.get('status') != 'verified': return False
        if not isinstance(item.get('reviewed_by'), str) or not item['reviewed_by'].strip(): return False
        reviewed_on=datetime.date.fromisoformat(item.get('reviewed_on',''))
        if reviewed_on>datetime.date.today(): return False
        if not isinstance(item.get('reference'), str) or not item['reference'].strip(): return False
        relative = Path(item['summary_path'])
        if relative.is_absolute() or relative.parts[:2] != ('docs','evidence') or '..' in relative.parts: return False
        candidate = root/relative
        current=root
        for part in relative.parts:
            current=current/part
            if current.is_symlink():return False
        if not candidate.resolve().is_relative_to((root/'docs/evidence').resolve()): return False
        data = reviewed_bytes(candidate)
        if len(data.strip()) < 80 or len(data)>256000: return False
        if hashlib.sha256(data).hexdigest() != item.get('sha256'): return False
        if key=='source_license_decided':
            if hashlib.sha256(reviewed_bytes(root/'LICENSE.txt')).hexdigest()!=item.get('license_sha256'):return False
        if key in ('commercial_connection_implemented_and_tested','voice_rights_review_complete',
                   'privacy_label_review_complete','security_review_complete', 'purchase_flow_tested',
                   'real_device_release_tests_complete','ad_privacy_and_lifecycle_tested',
                   'final_policies_review_complete','independent_security_review_complete'):
            if item.get('runtime_sha256') != source_fingerprint(root): return False
        return True
    except (OSError, ValueError, TypeError, KeyError, AttributeError):
        return False

def voice_assets_blockers(root=ROOT):
    try:
        voice=root/'vendor/voice'
        inventory=json.loads((voice/'inventory.json').read_text(encoding='utf-8'))
        item=json.loads((root/'release/evidence-index.json').read_text(encoding='utf-8'))['items']['voice_rights_review_complete']
        if not evidence_valid('voice_rights_review_complete',root):return ['voice_asset_review_invalid']
        hashes={'model_sha256':hashlib.sha256((voice/'model.vvm').read_bytes()).hexdigest(),
                'notice_sha256':hashlib.sha256((voice/'NOTICE.txt').read_bytes()).hexdigest(),
                'inventory_sha256':hashlib.sha256((voice/'inventory.json').read_bytes()).hexdigest()}
        if inventory.get('schema')!=1 or not inventory.get('speakers'):return ['voice_inventory_invalid']
        if any(item.get(key)!=sha for key,sha in hashes.items()):return ['voice_assets_differ_from_review']
        if any(inventory.get(key)!=hashes[key] for key in ('model_sha256','notice_sha256')):
            return ['voice_inventory_hash_mismatch']
        return []
    except (OSError,ValueError,TypeError,KeyError):return ['voice_asset_review_missing']
def revenue_ads_enabled(value):
    return value.get('status') == 'revenue_enabled' and all(value.get(key) is True
        for key in ['admob_account_and_terms_complete', 'ad_consent_messages_published',
                    'ad_privacy_and_lifecycle_tested', 'admob_app_readiness_approved', 'app_ads_txt_verified'])

def blockers(value, root=ROOT):
    if not isinstance(value,dict): return ['readiness_schema_invalid']
    failed = [key for key in REQUIRED if value.get(key) is not True]
    failed.extend(key+'_evidence_invalid' for key in REQUIRED
                  if value.get(key) is True and not evidence_valid(key, root))
    if not isinstance(value.get('operator_name'), str) or not value['operator_name'].strip(): failed.append('operator_name')
    if value.get('business_model') != 'free_with_nonconsumable_ad_removal' or value.get('base_app_price') != 'free': failed.append('business_model')
    if value.get('ad_removal_price_jpy') != 980 or isinstance(value.get('ad_removal_price_jpy'), bool): failed.append('ad_removal_price_jpy')
    if value.get('ad_removal_product_id') != 'jp.livetalk.mobile.remove_ads': failed.append('ad_removal_product_id')
    email=value.get('support_email')
    if not isinstance(email,str) or not re.fullmatch(r'[^\s@]+@[^\s@]+\.[^\s@]+', email): failed.append('support_email')
    for key, separator in [('admob_application_id', '~'), ('admob_banner_id', '/')]:
        v=value.get(key, '')
        if not isinstance(v,str) or not re.fullmatch(r'ca-app-pub-[0-9]{16}'+re.escape(separator)+r'[0-9]{10}', v) or v.startswith('ca-app-pub-3940256099942544'):
            failed.append(key)
    for key in ['support_url', 'privacy_policy_url', 'terms_url']:
        try:
            raw=value.get(key)
            if not isinstance(raw,str): raise ValueError('URL must be text')
            u = urlsplit(raw)
            if u.scheme != 'https' or not u.hostname or u.username or u.password: raise ValueError('Unsafe URL')
        except ValueError:failed.append(key)
    if value.get('carplay_marketed'):
        failed.extend(key for key in ['carplay_entitlement_approved', 'carplay_vehicle_tests_complete'] if value.get(key) is not True)
    # There is currently no approved paid connection adapter; a checklist cannot enable one.
    if not evidence_valid('commercial_connection_implemented_and_tested',root):
        failed.append('commercial_connection_evidence_missing')
    adapter = root/'ios/LiveTalk/CommercialChatGPTConnection.swift'
    if not adapter.is_file() or len(adapter.read_text(encoding='utf-8').strip()) < 100:
        failed.append('commercial_connection_adapter_missing')
    policy = root/'ios/LiveTalk/DistributionPolicy.swift'
    runtime = root/'ios/LiveTalk/ConversationRuntime.swift'
    if not policy.is_file() or not runtime.is_file() or not re.search(
        r'^\s*static let commercialConnectionAvailable\s*=\s*true\s*$', policy.read_text(encoding='utf-8'),re.M) or not re.search(
        r'^\s*(?:private )?(?:lazy )?var gpt\s*=\s*CommercialChatGPTConnection\s*[({]', runtime.read_text(encoding='utf-8'),re.M):
        failed.append('commercial_connection_adapter_unwired')
    # Publisher verification can depend on the first store listing; it gates revenue activation.
    if value.get('status') == 'revenue_enabled':
        failed.extend(key for key in ['admob_app_readiness_approved','app_ads_txt_verified'] if value.get(key) is not True)
        failed.extend(key+'_evidence_invalid' for key in ['admob_app_readiness_approved','app_ads_txt_verified']
                      if value.get(key) is True and not evidence_valid(key,root))
    return failed
if __name__ == '__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--report',type=Path);parser.add_argument('--assets',action='store_true');args=parser.parse_args()
    value=json.loads((ROOT/'release/store-readiness.json').read_text(encoding='utf-8')); failed=blockers(value)
    if args.assets:failed+=voice_assets_blockers()
    result={'ready':not failed,'blockers':failed,'checklist_is_not_legal_or_security_approval':True}
    if args.report: args.report.parent.mkdir(parents=True,exist_ok=True);args.report.write_text(json.dumps(result,indent=2)+'\n')
    print(json.dumps(result,ensure_ascii=False,indent=2))
    raise SystemExit(1 if failed else 0)
