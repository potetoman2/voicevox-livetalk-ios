#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
mkdir -p ios/build/storekit
xcodegen generate --spec tests/storekit/project.yml
DEVICE=$(xcrun simctl list devices available --json | python3 -c 'import sys,json; d=json.load(sys.stdin)["devices"]; choices=[v["udid"] for k,values in d.items() if "iOS-26" in k for v in values if v["isAvailable"] and v["name"].startswith("iPhone")]; assert choices, "An iOS 26 iPhone simulator is required"; print(choices[0])')
# Make cold simulator startup a separate, bounded operation with visible diagnostics.
# An unavailable runner must fail the check instead of silently waiting for the job limit.
python3 - "$DEVICE" <<'PY'
import subprocess, sys
subprocess.run(['xcrun', 'simctl', 'bootstatus', sys.argv[1], '-b'], check=True, timeout=240)
PY
xcodebuild test -project tests/storekit/LiveTalkCommerceTests.xcodeproj -scheme CommerceHost \
  -destination "platform=iOS Simulator,id=$DEVICE" -parallel-testing-enabled NO \
  -destination-timeout 60 -test-timeouts-enabled YES -maximum-test-execution-time-allowance 90 \
  -derivedDataPath ios/build/storekit/DerivedData -resultBundlePath ios/build/storekit/Commerce.xcresult \
  CODE_SIGNING_ALLOWED=NO | tee ios/build/storekit/test.log
