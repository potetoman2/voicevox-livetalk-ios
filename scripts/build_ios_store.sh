#!/usr/bin/env bash
set -euo pipefail
# Archive/export only. Upload and App Review submission are separate owner-approved steps.
project_root="$(cd "$(dirname "$0")/.." && pwd)"
[[ "$(uname -s)" == "Darwin" ]] || { echo 'App Store signing requires the macOS runner.' >&2; exit 1; }
cd "$project_root"
python3 scripts/check_store_release.py
python3 scripts/check_build_sdk.py
for variable in LIVETALK_CERT_P12_BASE64 LIVETALK_CERT_PASSWORD LIVETALK_PROFILE_BASE64 LIVETALK_APPLE_TEAM_ID RUNNER_TEMP; do
  [[ -n "${!variable:-}" ]] || { echo "Missing signing configuration: $variable" >&2; exit 1; }
done
[[ "${LIVETALK_CARPLAY:-disabled}" == "disabled" ]] || { echo 'CarPlay needs a separately reviewed distribution configuration.' >&2; exit 1; }
umask 077
signing_root="$(mktemp -d "$RUNNER_TEMP/livetalk-signing.XXXXXX")"
keychain_path="$signing_root/signing.keychain-db"
keychain_password="$(openssl rand -hex 32)"
profile_path=''
cleanup() {
  # Only paths created by this run are removed; existing profiles are never overwritten.
  if [[ -n "$profile_path" ]]; then rm -f -- "$profile_path"; fi
  security delete-keychain "$keychain_path" >/dev/null 2>&1 || true
  rm -f -- "$signing_root/certificate.p12" "$signing_root/profile.mobileprovision" "$signing_root/profile.plist" "$signing_root/identities.txt"
  rmdir "$signing_root" 2>/dev/null || true
}
trap cleanup EXIT
export LIVETALK_SIGNING_TEMP="$signing_root"
python3 - <<'PY'
import base64, os
from pathlib import Path
root=Path(os.environ['LIVETALK_SIGNING_TEMP'])
for name, variable in [('certificate.p12','LIVETALK_CERT_P12_BASE64'), ('profile.mobileprovision','LIVETALK_PROFILE_BASE64')]:
    (root/name).write_bytes(base64.b64decode(''.join(os.environ[variable].split()),validate=True))
PY
security create-keychain -p "$keychain_password" "$keychain_path"
security set-keychain-settings -lut 21600 "$keychain_path"
security unlock-keychain -p "$keychain_password" "$keychain_path"
security import "$signing_root/certificate.p12" -P "$LIVETALK_CERT_PASSWORD" -k "$keychain_path" -T /usr/bin/codesign -T /usr/bin/security >/dev/null
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$keychain_password" "$keychain_path" >/dev/null
security list-keychains -d user -s "$keychain_path" /Library/Keychains/System.keychain
security find-identity -v -p codesigning "$keychain_path" > "$signing_root/identities.txt"
security cms -D -i "$signing_root/profile.mobileprovision" > "$signing_root/profile.plist"
unset LIVETALK_CERT_P12_BASE64 LIVETALK_CERT_PASSWORD LIVETALK_PROFILE_BASE64
build_root="$project_root/ios/build/store"
mkdir -p "$build_root"
configuration="$(python3 scripts/store_signing.py "$signing_root/profile.plist" "$signing_root/identities.txt" --team-id "$LIVETALK_APPLE_TEAM_ID" --output "$build_root")"
profile_uuid="${configuration%%$'\n'*}"
identity_sha1="${configuration##*$'\n'}"
profile_directory="$HOME/Library/MobileDevice/Provisioning Profiles"
mkdir -p "$profile_directory"
candidate_profile="$profile_directory/$profile_uuid.mobileprovision"
[[ ! -e "$candidate_profile" ]] || { echo 'A profile with this UUID already exists; stop without overwriting it.' >&2; exit 1; }
cp "$signing_root/profile.mobileprovision" "$candidate_profile"
profile_path="$candidate_profile"
python3 - <<'PY'
import json, pathlib, plistlib, sys
sys.path.insert(0,'scripts')
from check_store_release import revenue_ads_enabled
p=pathlib.Path('ios/LiveTalk/Info.plist')
info=plistlib.loads(p.read_bytes())
release=json.loads(pathlib.Path('release/store-readiness.json').read_text(encoding='utf-8'))
info.update(LTExperimentalChatEnabled=False, LTPlanUsageEnabled=False,
            LTCommerceEnabled=True, LTCarPlayEnabled=False,
            LTRevenueAdsEnabled=revenue_ads_enabled(release),
            GADApplicationIdentifier=release['admob_application_id'],
            LTAdMobBannerID=release['admob_banner_id'])
info.pop('UIBackgroundModes',None)
p.write_bytes(plistlib.dumps(info))
PY
python3 scripts/prepare_native.py ios
python3 scripts/check_store_release.py --assets
cd "$project_root/ios"
xcodegen generate --spec project.yml
xcodebuild -resolvePackageDependencies -project LiveTalkMobile.xcodeproj -scheme LiveTalkMobile -derivedDataPath "$build_root/DerivedData"
python3 "$project_root/scripts/check_google_packages.py" "$build_root/DerivedData/SourcePackages" "$project_root/ios/LiveTalkMobile.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"
xcodebuild -project LiveTalkMobile.xcodeproj -scheme LiveTalkMobile -configuration Release -sdk iphoneos \
  -destination 'generic/platform=iOS' -derivedDataPath "$build_root/DerivedData" \
  -archivePath "$build_root/LiveTalk.xcarchive" -resultBundlePath "$build_root/archive.xcresult" \
  CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM="$LIVETALK_APPLE_TEAM_ID" \
  CODE_SIGN_IDENTITY="$identity_sha1" PROVISIONING_PROFILE_SPECIFIER="$profile_uuid" \
  OTHER_CODE_SIGN_FLAGS="--keychain $keychain_path" archive
codesign --verify --deep --strict "$build_root/LiveTalk.xcarchive/Products/Applications/LiveTalkMobile.app"
xcodebuild -exportArchive -archivePath "$build_root/LiveTalk.xcarchive" \
  -exportOptionsPlist "$build_root/ExportOptions.plist" -exportPath "$build_root/export"
[[ -f "$build_root/export/LiveTalkMobile.ipa" ]] || { echo 'Xcode did not export a signed IPA.' >&2; exit 1; }
shasum -a 256 "$build_root/export/LiveTalkMobile.ipa" > "$build_root/export/LiveTalkMobile.ipa.sha256"
python3 "$project_root/scripts/audit_ipa_privacy.py" "$build_root/export/LiveTalkMobile.ipa" --output "$build_root/export/privacy-package-audit.json"
echo 'Signed archive/export created. No upload, App Review submission or store release was performed.'
