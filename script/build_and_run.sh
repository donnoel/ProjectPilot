#!/bin/bash
set -euo pipefail

mode="${1:-run}"
case "$mode" in
  run|--build-only|--verify|--debug|--logs|--telemetry) ;;
  *) echo "Usage: $0 [--build-only|--verify|--debug|--logs|--telemetry]" >&2; exit 2 ;;
esac

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
build_root="$project_root/Build/Ticks"
app_bundle="$build_root/Build/Products/Debug/ProjectPilot.app"

if [[ "$mode" != --build-only ]]; then
  pkill -x ProjectPilot >/dev/null 2>&1 || true
fi

# Uses existing signing profiles; never changes the developer account implicitly.
# The sibling Tick checkout provides the first-party TickCore package.
xcodebuild -project "$project_root/ProjectPilot.xcodeproj" -scheme ProjectPilot \
  -configuration Debug -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath "$build_root" SWIFT_SUPPRESS_WARNINGS=NO \
  SWIFT_TREAT_WARNINGS_AS_ERRORS=YES GCC_TREAT_WARNINGS_AS_ERRORS=YES build

case "$mode" in
  --build-only) exit 0 ;;
  --debug) exec lldb -- "$app_bundle/Contents/MacOS/ProjectPilot" ;;
  *) open -n "$app_bundle" ;;
esac

case "$mode" in
  --verify) sleep 2; pgrep -x ProjectPilot >/dev/null ;;
  --logs) exec /usr/bin/log stream --info --style compact --predicate 'process == "ProjectPilot"' ;;
  --telemetry) exec /usr/bin/log stream --info --style compact --predicate 'subsystem == "dn.ProjectPilot"' ;;
esac
