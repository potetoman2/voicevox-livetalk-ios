"""Check the toolchain required for App Store uploads since 2026-04-28."""
import json, re, subprocess

version = subprocess.check_output(['xcodebuild', '-version'], text=True)
sdk = subprocess.check_output(['xcrun', '--sdk', 'iphoneos', '--show-sdk-version'], text=True).strip()
xcode = re.search(r'Xcode\s+(\d+)', version)
if not xcode or int(xcode[1]) < 26 or int(sdk.split('.')[0]) < 26:
    raise SystemExit('App Store submission requires Xcode 26+ and the iOS 26+ SDK.')
print(json.dumps({'xcode': version.strip(), 'iphoneos_sdk': sdk, 'requirement_met': True}))
