"""Check publication content and a small set of security invariants, without exposing secrets."""
import json, re, subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
files=subprocess.check_output(['git','ls-files','-z'],cwd=ROOT).decode().split('\0')
findings=[]
for name in filter(None,files):
    path=Path(name)
    if path.suffix in ['.p8','.p12','.pfx','.pem','.key','.mobileprovision'] or path.name.startswith('.env'):
        findings.append({'file':name,'issue':'credential_file'})
    if path.suffix not in ['.swift','.py','.sh','.md','.json','.js','.cjs','.yml','.txt','.html','.plist','.xcprivacy']: continue
    content=(ROOT/name).read_text(encoding='utf-8')
    if re.search(r'-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----|\b(?:ghp|github_pat|sk_live)_[A-Za-z0-9]{25,}|\bsk-proj-[A-Za-z0-9_-]{40,}',content):
        findings.append({'file':name,'issue':'possible_secret'})
controller=(ROOT/'ios/LiveTalk/LiveTalkController.swift').read_text(encoding='utf-8')
html=(ROOT/'shared/index.html').read_text(encoding='utf-8')
checks={'local_ui_origin_guard':'LocalBridgePolicy.allowed(message.frameInfo.request.url' in controller,
 'exact_webview_guard':'message.webView === app' in controller,
 'protected_temporary_audio':'.completeFileProtection' in controller,
 'explicit_data_consent':'confirmDataConsent()' in controller,
 'no_remote_ui_connections':"connect-src 'none'" in html,
 'no_frame_or_object_loading':"frame-src 'none'; object-src 'none'" in html}
findings.extend({'issue':name} for name,ok in checks.items() if not ok)
print(json.dumps({'checked_files':len(list(filter(None,files))),'invariant_checks':checks,'findings':findings,'scope':'Static publication checks; not a penetration test or guarantee.'},indent=2))
raise SystemExit(bool(findings))
