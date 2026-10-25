#!/bin/bash
# Run a chosen local check using installed tools; never installs or changes global defaults.
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ $# -eq 0 ]]; then
  echo 'Usage: bash scripts/local-check.sh <command> [args...] (choose a focused check; no implicit full suite)' >&2
  exit 2
fi
if [[ "${GITHUB_ACTIONS:-}" == true ]]; then
  echo 'This launcher is for local checks. GitHub must use the existing ci.sh contract.' >&2
  exit 2
fi
expected_xcode=26.6
# Honor an explicit compiler choice. Otherwise prefer the already-installed CI baseline.
if [[ -z "${DEVELOPER_DIR:-}" ]]; then
  for local_xcode_app in "/Applications/Xcode-$expected_xcode.app" "$HOME/Applications/Xcode-$expected_xcode.app"; do
    if [[ -x "$local_xcode_app/Contents/Developer/usr/bin/xcodebuild" ]] &&
       [[ "$("$local_xcode_app/Contents/Developer/usr/bin/xcodebuild" -version | sed -n '1p')" == "Xcode $expected_xcode" ]]; then
      export DEVELOPER_DIR="$local_xcode_app/Contents/Developer"
      break
    fi
  done
fi
local_xcode_version="$(xcodebuild -version 2>/dev/null | sed -n '1p' || true)"
printf 'Local check: %s; developer directory: %s\n' "${local_xcode_version:-unavailable}" "${DEVELOPER_DIR:-$(xcode-select -p 2>/dev/null || true)}" >&2
if [[ "$local_xcode_version" != "Xcode $expected_xcode" ]]; then
  echo "Installed CI Xcode $expected_xcode was not selected. Focused checks may use this compiler; report the difference. ci.sh still requires its pinned baseline. Do not install tools just to run an unrelated check." >&2
fi
exec "$@"
