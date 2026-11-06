#!/usr/bin/env bash
# Incremental optimized build of <workdir>/zed, staged into <workdir>/out with
# the nixpkgs layout:
#
#   out/bin/zeditor                  the CLI (finds ../libexec/zed-editor)
#   out/libexec/zed-editor           wrapper adding nodejs + bubblewrap to PATH
#   out/libexec/.zed-editor-wrapped  the app, libGL/vulkan/wayland on its RUNPATH
#
# cargo keeps zed/target, so only changed crates rebuild. release-fast is
# upstream's profile (optimized, no LTO, 16 codegen units); debug info is off
# to keep linking and the target dir small.
#
#   scripts/dev-build.sh <workdir> [extra cargo args]
set -euo pipefail
repo=$(cd "$(dirname "$0")/.." && pwd)

if [ -z "${GEN7_ZED_RUNTIME_RPATH:-}" ]; then
  # --profile keeps a GC root, so the libraries on the RUNPATH stay around.
  mkdir -p "$1"
  exec nix develop "$repo" --profile "$1/.dev-profile" -c "$0" "$@"
fi

work=$(cd "$1" && pwd)
shift
profile=release-fast
cd "$work/zed"
CARGO_PROFILE_RELEASE_FAST_DEBUG=false \
  cargo build --profile "$profile" --package zed --package cli "$@"

target=$work/zed/target/$profile
out=$work/out
mkdir -p "$out/bin" "$out/libexec"
install -m 0755 "$target/cli" "$out/bin/zeditor"
install -m 0755 "$target/zed" "$out/libexec/.zed-editor-wrapped"
patchelf --add-rpath "$GEN7_ZED_RUNTIME_RPATH" "$out/libexec/.zed-editor-wrapped"
cat >"$out/libexec/zed-editor" <<EOF
#!/usr/bin/env bash
PATH="\${PATH:+\$PATH:}$GEN7_ZED_RUNTIME_PATH" exec -a "\$0" "$out/libexec/.zed-editor-wrapped" "\$@"
EOF
chmod 0755 "$out/libexec/zed-editor"
echo "built: $out/bin/zeditor"
