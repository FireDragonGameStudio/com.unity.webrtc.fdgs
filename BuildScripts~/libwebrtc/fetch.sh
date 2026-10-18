#!/bin/bash
# Fetches libwebrtc branch-heads/<branch> with its dependencies for <target_os> into $WEBRTC_ROOT
# (default: $RUNNER_TEMP/webrtc, or ./webrtc).
# Usage: fetch.sh <branch> <target_os>   e.g. fetch.sh 8078 linux

branch="$1"
target_os="$2"
set -euo pipefail

root="${WEBRTC_ROOT:-${RUNNER_TEMP:-$PWD}/webrtc}"

mkdir -p "$root"
cd "$root"
if [ ! -d depot_tools ]; then
  git clone --depth 1 https://chromium.googlesource.com/chromium/tools/depot_tools.git
fi
export PATH="$root/depot_tools:$PATH"
# Bootstraps depot_tools (its Python and tool wrappers) on first use.
update_depot_tools

cat > .gclient <<GCLIENT
solutions = [{
  "name": "src",
  "url": "https://webrtc.googlesource.com/src.git@refs/branch-heads/${branch}",
  "deps_file": "DEPS",
  "managed": False,
  "custom_deps": {},
}]
target_os = ["${target_os}"]
GCLIENT

gclient sync --no-history --shallow --with_branch_heads -D
echo "libwebrtc: $(git -C src log -1 --format='%H %s')"
df -h "$root"
