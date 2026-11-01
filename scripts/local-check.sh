#!/bin/bash
# Fixed local Xcode; hosted CI keeps its own contract. No downloads or global switches.
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ $# -eq 0 ]]; then
  echo 'Usage: bash scripts/local-check.sh <command> [args...] (choose a focused check; no implicit full suite)' >&2
  exit 2
fi
if [[ "${GITHUB_ACTIONS:-}" == true ]]; then
  echo 'This launcher is local only. GitHub must use its existing ci.sh contract.' >&2
  exit 2
fi
pinned_developer_dir=/Applications/Xcode-27-RC.app/Contents/Developer
if [[ -n "${DEVELOPER_DIR:-}" && "$DEVELOPER_DIR" != "$pinned_developer_dir" ]]; then
  echo 'Local work uses the fixed Xcode 27 installation. A conflicting DEVELOPER_DIR was supplied; no command was run.' >&2
  exit 2
fi
if [[ ! -x "$pinned_developer_dir/usr/bin/xcodebuild" ]]; then
  echo 'Pinned Xcode 27 is missing. No older compiler or download was selected. See DevSystem/notes/APPLE-LOCAL-TARGETS.md.' >&2
  exit 2
fi
export DEVELOPER_DIR="$pinned_developer_dir"
local_xcode_version="$(/usr/bin/xcodebuild -version)"
if [[ "$local_xcode_version" != $'Xcode 27.0\nBuild version 27A266a' ]]; then
  echo 'Pinned Xcode version/build changed. Review the shared local baseline before proceeding.' >&2
  exit 2
fi
printf 'Local check: Xcode 27.0 (27A266a); %s\n' "$DEVELOPER_DIR" >&2
exec "$@"
