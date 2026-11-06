#!/usr/bin/env bash
# Regenerate patches/ from the working-copy changes of a Zed checkout (a jj or
# git repo at the release tag the locked nixpkgs builds).
#
#   scripts/update-patches.sh path/to/zed
#
# Each patch covers a fixed set of files; anything else changed in the checkout
# (for example local notes) is left out.
set -euo pipefail
here=$(cd "$(dirname "$0")/.." && pwd)
zed=$(cd "${1:?usage: $0 path/to/zed}" && pwd)

declare -A patch_files=(
  [0001-gpui_wgpu-skip-redundant-fragment-work]="crates/gpui_wgpu/src/shaders.wgsl"
  [0002-gpui_linux-start-frames-before-the-compositor-callback]="crates/gpui_linux/src/linux/wayland/window.rs"
)

for name in "${!patch_files[@]}"; do
  # shellcheck disable=SC2086 # file lists are space separated on purpose
  (cd "$zed" && git diff --no-color --no-ext-diff HEAD -- ${patch_files[$name]}) >"$here/patches/$name.patch"
  if [ ! -s "$here/patches/$name.patch" ]; then
    echo "no changes for $name in $zed" >&2
    exit 1
  fi
  echo "patches/$name.patch"
done
