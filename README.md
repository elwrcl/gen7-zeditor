# gen7-zeditor

[Zed](https://zed.dev) from nixpkgs with a few patches that make it usable on
slow GPUs. It is developed on an Intel HD Graphics 4000 (Ivy Bridge, Gen7)
laptop, where stock Zed scrolls at ~13 fps on a 1080p screen; with these patches
it reaches ~60 fps.

The flake builds nixpkgs' `zed-editor` with the patches in [`patches/`](patches)
applied. CI builds every change and pushes it to the
[`zeditor`](https://zeditor.cachix.org) Cachix cache, so consumers download the
result instead of compiling Zed.

## Why stock Zed is slow on old GPUs

Zed's renderer (GPUI on wgpu) redraws the whole window every frame. Profiling
with apitrace on the HD 4000 at 1920×1060 showed ~52 ms of GPU time per frame:

| Work per frame | GPU time | Cause |
|---|---|---|
| Window drop shadow | ~16 ms | blur shader evaluated for every pixel of the window, interior included |
| Overlapping background quads | ~15 ms | every pixel loads its quad record from a storage buffer |
| Bordered and rounded quads | ~14 ms | same, plus the SDF math |
| Quads outside their clip rect | ~6 ms | rasterized in full, discarded in the fragment shader |
| Text | 0.06 ms | |

That is ~12 fragment shader invocations per pixel. A modern GPU does this in a
millisecond; the HD 4000's 16 EUs need 50. The cost scales with window area,
which is why a small Zed window felt fine while a full screen one did not.

Once the GPU side was fixed, a second limit showed up: GPUI does not start a
frame until the compositor's frame callback for the previous one arrives, so
CPU (~14 ms), GPU (~7 ms) and composition run one after another and most frames
miss the 16.7 ms refresh interval.

## Patches

- **`0001-gpui_wgpu-skip-redundant-fragment-work`** (shaders only, output is
  pixel-identical):
  - quad and shadow geometry is clipped to the content mask in the vertex shader,
    so masked-out pixels are never rasterized;
  - the vertex shader passes the "plain solid background" interior of a quad as a
    flat varying, and those pixels return without loading the quad record;
  - pixels deep inside a drop shadow (past the gaussian tail and corner radius)
    return full coverage without running the blur loop.

  GPU time per frame: 52 ms → 7.2 ms.

- **`0002-gpui_linux-start-frames-before-the-compositor-callback`** (Wayland):
  when a redraw is requested while the last frame's callback is still pending,
  the next frame starts right away, at most one frame ahead. FIFO presentation
  still paces frames to the display (the next swap waits for the previous frame
  to be shown). It only kicks in while the compositor delivers callbacks at
  display rate, so windows on hidden workspaces, which still get the occasional
  callback, never block in a swap. Set `GEN7_ZEDITOR_EAGER_FRAMES=0` to turn it
  off.

### Measurements

HD 4000, niri, tiled full-width window on a 1920×1080 monitor, 2923-line Rust
file, OpenGL backend:

| Scenario | Stock Zed 1.25.3 | Patched |
|---|---|---|
| Holding an arrow key (35 repeats/s), frames drawn/s | 13.3 | 58.7 |
| Wheel scrolling, frames drawn/s | 13.3 | 48.2 |
| Wheel scrolling, laptop panel (1366×768) | – | 59.1 |

## Using it

### NixOS / home-manager

```nix
{
  inputs.gen7-zeditor.url = "github:elwrcl/gen7-zeditor";
  # Do not add `inputs.nixpkgs.follows` here: the cache only has builds for the
  # nixpkgs revision locked in this repo.
}
```

Trust the cache on the host, otherwise Zed is built locally (that takes hours on
the hardware this is meant for):

```nix
nix.settings = {
  substituters = [ "https://zeditor.cachix.org" ];
  trusted-public-keys = [
    "zeditor.cachix.org-1:xYqrNAPukHTxXEJokxHyBK2XVq+raS75I8L2aYcIC4Y="
  ];
};
```

Then use the package, for example with home-manager:

```nix
programs.zed-editor = {
  enable = true;
  package = inputs.gen7-zeditor.packages.x86_64-linux.zed-editor;
};
```

`overlays.default` applies the same patches to your own nixpkgs' `zed-editor`,
but that build will not be in the cache unless the revisions match.

### Try it without installing

```sh
nix run github:elwrcl/gen7-zeditor
```

## Settings that help on slow GPUs

- On a tiling compositor that does not tell windows they are tiled (niri without
  `prefer-no-csd`, for example), Zed draws its own window shadow on every frame.
  `"window_decorations": "server"` in Zed's settings avoids that.

## Updates

A weekly workflow updates nixpkgs, builds Zed with the patches and only commits
the new lock when the build succeeds, so the lock never points at an uncached
build. A failed run usually means a new Zed release changed the patched code and
the patches need rebasing.

## Working on the patches

`nix build` recompiles all of Zed for every change. For iterating there is an
incremental setup that uses the dev shell (same toolchain, libraries and
vendored crates as the package):

```sh
scripts/dev-setup.sh ../zed-work   # once: Zed at the locked tag + patches, vendored crates
scripts/dev-build.sh ../zed-work   # after each change
../zed-work/out/bin/zeditor
```

The first build takes as long as a full build; after that, a change to
`gpui_linux` or `gpui_wgpu` rebuilds in about six minutes on an i5-3210M
(`release-fast` profile: no LTO, 16 codegen units). Edit `../zed-work/zed`, then
regenerate the patches with `scripts/update-patches.sh ../zed-work/zed`.

## License

GPL-3.0-or-later, like Zed itself. The patches modify Zed's source; Zed's own
licenses apply to everything they touch.
