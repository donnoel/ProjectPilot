#!/bin/bash
# Same build and test contract locally and on GitHub. No retries or disabled assertions.
set -euo pipefail
cd "$(dirname "$0")/.."
export TZ=UTC LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8
phase="${1:-all}"
case "$phase" in environment|build|unit|ui|all) ;; *) echo "Usage: bash scripts/ci.sh {environment|build|unit|ui|all}" >&2; exit 2 ;; esac
expected_xcode=26.6
project=ProjectPilot.xcodeproj
scheme=ProjectPilot
ui_target=ProjectPilotUITests
actual_xcode="$(xcodebuild -version | sed -n '1p')"
if [[ "$actual_xcode" != "Xcode $expected_xcode" ]]; then
  echo "CI requires Xcode $expected_xcode; found $actual_xcode. Select it with DEVELOPER_DIR before running this check." >&2
  exit 2
fi
printf 'Commit: %s\nToolchain: %s\nDeveloper directory: %s\nTimezone: %s; test language/region: en/US\n' "$(git rev-parse HEAD)" "$actual_xcode" "$(xcode-select -p)" "$TZ"
destination='platform=macOS,arch=arm64'
if [[ "$phase" == environment ]]; then exit 0; fi
DERIVED_DATA="${DERIVED_DATA:-$PWD/DerivedData}"
RESULT_BUNDLE="${RESULT_BUNDLE:-${TMPDIR:-/tmp}/ProjectPilot-$(uuidgen).xcresult}"
args=(
  -project "$project" -scheme "$scheme" -configuration Debug
  -destination "$destination" -derivedDataPath "$DERIVED_DATA"
  CODE_SIGN_IDENTITY=-
  CODE_SIGN_STYLE=Manual
  DEVELOPMENT_TEAM=
  CODE_SIGN_ENTITLEMENTS=
  SWIFT_SUPPRESS_WARNINGS=NO
  SWIFT_TREAT_WARNINGS_AS_ERRORS=YES
  GCC_TREAT_WARNINGS_AS_ERRORS=YES
)
build() {
  xcodebuild "${args[@]}" clean build-for-testing
}
run_tests() {
  local kind="$1"
  local selection=()
  if [[ "$kind" == unit ]]; then selection=("-skip-testing:$ui_target"); else selection=("-only-testing:$ui_target"); fi
  local result="${RESULT_BUNDLE%.xcresult}-$kind.xcresult"
  mkdir -p "$(dirname "$result")"
  xcodebuild "${args[@]}" -resultBundlePath "$result" \
    -parallel-testing-enabled NO -maximum-concurrent-test-simulator-destinations 1 \
    -testLanguage en -testRegion US "${selection[@]}" test-without-building
}
case "$phase" in
  build) build ;;
  unit|ui) run_tests "$phase" ;;
  all) build; run_tests unit; run_tests ui ;;
esac
