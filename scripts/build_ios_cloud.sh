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
python3 - <<'PY'
import os, pathlib, plistlib
p=pathlib.Path("ios/LiveTalk/Info.plist")
value=plistlib.loads(p.read_bytes())
value["LTExperimentalChatEnabled"]=os.environ["LIVETALK_DISTRIBUTION"] == "preview"
p.write_bytes(plistlib.dumps(value))
PY
python3 "$project_root/scripts/prepare_native.py" ios
cd "$project_root/ios"
xcodegen generate --spec project.yml
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
