{
  description = "Zed editor patched for Intel Gen7 (Ivy Bridge) and other slow GPUs";

  # Only `nix build` from this repo reads these; NixOS hosts add the cache to
  # nix.settings themselves (see README).
  nixConfig = {
    extra-substituters = [ "https://zeditor.cachix.org" ];
    extra-trusted-public-keys = [
      "zeditor.cachix.org-1:xYqrNAPukHTxXEJokxHyBK2XVq+raS75I8L2aYcIC4Y="
    ];
  };

  # Consumers should not make this follow their own nixpkgs: the binary cache
  # only has builds for the revision locked here.
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
      inherit (pkgs) lib;

      patches = [
        ./patches/0001-gpui_wgpu-skip-redundant-fragment-work.patch
        ./patches/0002-gpui_linux-start-frames-before-the-compositor-callback.patch
        ./patches/0003-gpui_wgpu-read-wgpu-instance-flags-from-the-environment.patch
      ];

      patchZed =
        zed-editor:
        (zed-editor.override { buildRemoteServer = false; }).overrideAttrs (old: {
          patches = (old.patches or [ ]) ++ patches;
          # The upstream test suite roughly doubles an already long build.
          doCheck = false;
          meta = old.meta // {
            description = "${old.meta.description} (patched for slow GPUs, gen7-zeditor)";
          };
        });
    in
    {
      packages.${system} = {
        zed-editor = patchZed pkgs.zed-editor;
        default = self.packages.${system}.zed-editor;
      };

      # Same patches on top of the consumer's own zed-editor. Note: that build is
      # not in the binary cache unless the nixpkgs revisions match.
      overlays.default = final: prev: {
        zed-editor = patchZed prev.zed-editor;
      };

      # Environment for incremental `cargo build`s of a Zed checkout with the
      # same toolchain and libraries as the package (scripts/dev-*.sh).
      devShells.${system}.default = pkgs.mkShell {
        inputsFrom = [ pkgs.zed-editor ];
        packages = [ pkgs.patchelf ];

        env = {
          OPENSSL_NO_VENDOR = "1";
          LIBGIT2_NO_VENDOR = "1";
          LIBSQLITE3_SYS_USE_PKG_CONFIG = "1";
          ZSTD_SYS_USE_PKG_CONFIG = "1";
          ALLOW_MISSING_LICENSES = "1";
          ZED_UPDATE_EXPLANATION = pkgs.zed-editor.env.ZED_UPDATE_EXPLANATION;
          RELEASE_VERSION = pkgs.zed-editor.version;
          LK_CUSTOM_WEBRTC = pkgs.zed-editor.env.LK_CUSTOM_WEBRTC;

          # Read by scripts/dev-setup.sh: nixpkgs' vendored crates and the glib
          # headers its webrtc-sys fix points at.
          GEN7_ZED_VERSION = pkgs.zed-editor.version;
          GEN7_ZED_VENDOR = "${pkgs.zed-editor.cargoDeps}";
          GEN7_ZED_GLIB_INCLUDE = "${lib.getInclude pkgs.glib}/include/glib-2.0";
          GEN7_ZED_GLIB_CONFIG_INCLUDE = "${lib.getLib pkgs.glib}/lib/glib-2.0/include";

          # Read by scripts/dev-build.sh: what nixpkgs' postFixup adds.
          GEN7_ZED_RUNTIME_RPATH = lib.makeLibraryPath [
            pkgs.libGL
            pkgs.vulkan-loader
            pkgs.wayland
          ];
          GEN7_ZED_RUNTIME_PATH = lib.makeBinPath [
            pkgs.nodejs
            pkgs.bubblewrap
          ];
        };
      };

      formatter.${system} = pkgs.nixfmt;
    };
}
