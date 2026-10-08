#!/usr/bin/env bash
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
if [[ "$(uname -s)" != "Darwin" ]]; then
  echo 'This script runs on the GitHub macOS runner, not on Windows.' >&2
  exit 1
fi
build_root="$project_root/ios/build/cloud"
mkdir -p "$build_root"
cd "$project_root"
export LIVETALK_DISTRIBUTION="${LIVETALK_DISTRIBUTION:-preview}"
[[ "$LIVETALK_DISTRIBUTION" == "preview" || "$LIVETALK_DISTRIBUTION" == "store" ]] || { echo 'Invalid distribution flavor' >&2; exit 1; }
if [[ "$LIVETALK_DISTRIBUTION" == "store" ]]; then python3 scripts/check_store_release.py; fi
python3 scripts/check_build_sdk.py
python3 - <<'PY'
import os, pathlib, plistlib
p=pathlib.Path("ios/LiveTalk/Info.plist")
value=plistlib.loads(p.read_bytes())
value["LTExperimentalChatEnabled"]=False
# Rights-reserved preparation has no verified private-client permission.
value["LTPlanUsageEnabled"]=False
value["LTCommerceEnabled"]=os.environ["LIVETALK_DISTRIBUTION"] == "store"
value["LTRevenueAdsEnabled"]=False
if value["LTCommerceEnabled"]:
    import json
    release=json.loads(pathlib.Path("release/store-readiness.json").read_text())
    import sys
    sys.path.insert(0,'scripts')
    from check_store_release import revenue_ads_enabled
    value["LTRevenueAdsEnabled"]=revenue_ads_enabled(release)
    value["GADApplicationIdentifier"]=release["admob_application_id"]
    value["LTAdMobBannerID"]=release["admob_banner_id"]
else:
    value["GADApplicationIdentifier"]="ca-app-pub-3940256099942544~1458002511"
    value["LTAdMobBannerID"]="ca-app-pub-3940256099942544/2435281174"
# The restricted capability must not be signed by a free personal account.
if os.environ.get("LIVETALK_CARPLAY", "disabled") != "disabled":
    raise SystemExit("CarPlay approval and locked-device verification need a separate reviewed build.")
value["LTCarPlayEnabled"]=False
if value["LTCarPlayEnabled"]:
    value["UIBackgroundModes"]=["audio"]
p.write_bytes(plistlib.dumps(value))
PY
python3 "$project_root/scripts/prepare_native.py" ios
cd "$project_root/ios"
if [[ "${LIVETALK_CARPLAY:-}" == "approved" ]]; then
  python3 - <<'PY'
from pathlib import Path
p=Path('project.yml')
s=p.read_text().replace('        CODE_SIGN_STYLE: Automatic', '        CODE_SIGN_STYLE: Automatic\n        CODE_SIGN_ENTITLEMENTS: CarPlay.entitlements')
p.write_text(s)
PY
fi
xcodegen generate --spec project.yml
xcodebuild -resolvePackageDependencies -project LiveTalkMobile.xcodeproj -scheme LiveTalkMobile -derivedDataPath "$build_root/DerivedData"
python3 "$project_root/scripts/check_google_packages.py" "$build_root/DerivedData/SourcePackages" "$project_root/ios/LiveTalkMobile.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved" | tee "$build_root/google-packages.json"
xcodebuild \
  -project LiveTalkMobile.xcodeproj \
  -scheme LiveTalkMobile \
  -configuration Release \
  -sdk iphoneos \
  -destination 'generic/platform=iOS' \
  -derivedDataPath "$build_root/DerivedData" \
  -resultBundlePath "$build_root/build.xcresult" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY= \
  DEVELOPMENT_TEAM= \
  build 2>&1 | tee "$build_root/build.log"

app_path="$build_root/DerivedData/Build/Products/Release-iphoneos/LiveTalkMobile.app"
[[ -d "$app_path" ]] || { echo 'Xcode did not produce an iPhone app.' >&2; exit 1; }
# The output is for signing on Windows, including all embedded frameworks.
while IFS= read -r -d '' bundle; do
  if codesign -d "$bundle" >/dev/null 2>&1; then
    codesign --remove-signature "$bundle"
  fi
done < <(find "$app_path" \( -type d -name '*.framework' -o -type f -name '*.dylib' \) -print0)
if codesign -d "$app_path" >/dev/null 2>&1; then codesign --remove-signature "$app_path"; fi
python3 "$project_root/scripts/package_ipa.py" "$app_path" "$build_root/VOICEVOX_LiveTalk_iOS_UNSIGNED.ipa"
python3 "$project_root/scripts/audit_ipa_privacy.py" "$build_root/VOICEVOX_LiveTalk_iOS_UNSIGNED.ipa" --output "$build_root/privacy-package-audit.json"
