#!/bin/bash
# One command for all checks: format lint, version sync, package tests, app build and unit tests.
#   scripts/check.sh        package + app unit tests
#   scripts/check.sh --ui   also run UI tests (needs Accessibility permission the first time)
set -euo pipefail
cd "$(dirname "$0")/.."

ui=false
[ "${1:-}" = "--ui" ] && ui=true

step() { printf '\n==> %s\n' "$1"; }

step "swift-format lint"
swift format lint --strict --recursive App AppTests UITests Packages/CompressorKit/Sources Packages/CompressorKit/Tests

step "Version sync"
python3 scripts/update_version.py status

step "CompressorKit tests"
swift test --package-path Packages/CompressorKit --quiet

step "Generate Xcode project"
xcodegen generate --quiet

step "App build and tests"
tests=(-only-testing:VacpackTests)
$ui && tests=()
mkdir -p .build
if ! xcodebuild -project Vacpack.xcodeproj -scheme Vacpack -destination 'platform=macOS' \
  -derivedDataPath .build/xcode test ${tests[@]+"${tests[@]}"} >.build/xcodebuild.log 2>&1; then
  grep -E 'error:|failed|runFirstLaunch' .build/xcodebuild.log | head -20 >&2
  echo "xcodebuild failed; full log: .build/xcodebuild.log" >&2
  exit 1
fi
echo "App tests passed: $(grep -cE "Test Case '.*' passed" .build/xcodebuild.log)"

printf '\nAll checks passed.\n'
