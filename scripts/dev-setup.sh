#!/usr/bin/env bash
# One-time setup of a work directory for incremental Zed builds:
#
#   <workdir>/zed/     Zed at the tag the locked nixpkgs builds, patches applied
#                      as working-copy changes
#   <workdir>/vendor/  nixpkgs' vendored crates, with nixpkgs' webrtc-sys fix
#   <workdir>/.cargo/  cargo config pointing crates.io and git deps at vendor/
#                      (cargo also reads config from parent directories)
#
#   scripts/dev-setup.sh <workdir>
set -euo pipefail
repo=$(cd "$(dirname "$0")/.." && pwd)

if [ -z "${GEN7_ZED_VENDOR:-}" ]; then
  exec nix develop "$repo" -c "$0" "$@"
fi

work=$(mkdir -p "$1" && cd "$1" && pwd)

if [ ! -d "$work/zed" ]; then
  git clone --depth 1 --branch "v$GEN7_ZED_VERSION" https://github.com/zed-industries/zed "$work/zed"
  for patch in "$repo"/patches/*.patch; do
    git -C "$work/zed" apply "$patch"
  done
fi

if [ ! -d "$work/vendor" ]; then
  cp -r --no-preserve=mode "$GEN7_ZED_VENDOR" "$work/vendor.tmp"
  # Same substitutions as nixpkgs' postPatch: link the shared libwebrtc from
  # LK_CUSTOM_WEBRTC, and take glib headers from the store instead of a sysroot.
  for build_rs in "$work"/vendor.tmp/*/webrtc-sys-*/build.rs; do
    sed -i \
      -e 's|cargo:rustc-link-lib=static=webrtc|cargo:rustc-link-lib=dylib=webrtc|' \
      -e "s|builder.include(&glib_path);|builder.include(\"$GEN7_ZED_GLIB_INCLUDE\");|" \
      -e "s|builder.include(&glib_path_config);|builder.include(\"$GEN7_ZED_GLIB_CONFIG_INCLUDE\");|" \
      "$build_rs"
    grep -q 'dylib=webrtc' "$build_rs"
  done
  mv "$work/vendor.tmp" "$work/vendor"
fi

mkdir -p "$work/.cargo"
sed "s|@vendor@|$work/vendor|g" "$work/vendor/.cargo/config.toml" >"$work/.cargo/config.toml"

echo "ready; build with: $repo/scripts/dev-build.sh $work"
