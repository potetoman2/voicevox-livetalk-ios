#!/usr/bin/env bash
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
if [[ "$(uname -s)" != "Darwin" ]]; then echo 'iPhone版のビルドにはMacとXcodeが必要です。'; exit 1; fi
command -v xcodegen >/dev/null || { echo 'XcodeGenを用意してください（brew install xcodegen）。'; exit 1; }
python3 "$project_root/scripts/prepare_native.py" ios
cd "$project_root/ios"
xcodegen generate --spec project.yml
echo 'LiveTalkMobile.xcodeprojをXcodeで開き、SigningのTeamとBundle Identifierを設定して実機で実行してください。'
