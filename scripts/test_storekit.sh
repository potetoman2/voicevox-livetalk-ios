#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
mkdir -p ios/build/storekit
xcodegen generate --spec tests/storekit/project.yml
DEVICE=$(xcrun simctl list devices available --json | python3 -c 'import sys,json; d=json.load(sys.stdin)["devices"]; choices=[v["udid"] for k,values in d.items() if "iOS-26" in k for v in values if v["isAvailable"] and v["name"].startswith("iPhone")]; assert choices, "An iOS 26 iPhone simulator is required"; print(choices[0])')
xcodebuild test -project tests/storekit/LiveTalkCommerceTests.xcodeproj -scheme CommerceHost \
  -destination "platform=iOS Simulator,id=$DEVICE" -parallel-testing-enabled NO \
  -derivedDataPath ios/build/storekit/DerivedData -resultBundlePath ios/build/storekit/Commerce.xcresult \
  CODE_SIGNING_ALLOWED=NO | tee ios/build/storekit/test.log
