{
  description = "Misfortune, a launcher built for Calamity Client (prebuilt release binaries)";

  # The launcher's source is closed. This flake only repackages the binaries
  # published as GitHub releases of this repo; versions and hashes are pinned
  # in ./sources.json (refresh with ./update.sh after each release).

  inputs.nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";

  outputs =
    { self, nixpkgs }:
    let
      inherit (nixpkgs) lib;

      sources = lib.importJSON ./sources.json;
      systems = builtins.attrNames sources.platforms;

      # The launcher is unfree; allow just this package so `nix run` works
      # without NIXPKGS_ALLOW_UNFREE.
      eachSystem =
        f:
        lib.genAttrs systems (
          system:
          f (
            import nixpkgs {
              inherit system;
              config.allowUnfreePredicate = pkg: lib.getName pkg == "misfortune";
            }
          )
        );

      mkMisfortune =
        pkgs:
        let
          inherit (pkgs) stdenv;
          platform = sources.platforms.${stdenv.hostPlatform.system};

          # Linked directly by the binary.
          linkedLibs = with pkgs; [
            stdenv.cc.cc.lib # libgcc_s
            libxcb
            libxkbcommon
          ];

          # Loaded with dlopen by gpui at runtime, so they must be on the rpath.
          dlopenLibs = with pkgs; [
            fontconfig
            freetype
            libxkbcommon
            wayland
            vulkan-loader
            libx11
            libxcb
          ];
        in
        stdenv.mkDerivation {
          pname = "misfortune";
          inherit (sources) version;

          src = pkgs.fetchurl {
            url = "https://github.com/tragedy-mc/misfortune-releases/releases/download/v${sources.version}/${platform.asset}";
            inherit (platform) hash;
          };

          # The tarball has no top-level directory.
          sourceRoot = ".";

          nativeBuildInputs = lib.optionals stdenv.hostPlatform.isLinux [ pkgs.autoPatchelfHook ];
          buildInputs = lib.optionals stdenv.hostPlatform.isLinux linkedLibs;
          runtimeDependencies = lib.optionals stdenv.hostPlatform.isLinux dlopenLibs;

          dontConfigure = true;
          dontBuild = true;
          dontStrip = true;

          installPhase = ''
            runHook preInstall
            install -Dm755 misfortune $out/bin/misfortune
            install -Dm644 LICENSE $out/share/licenses/misfortune/LICENSE
            install -Dm644 THIRD_PARTY_NOTICES.txt $out/share/licenses/misfortune/THIRD_PARTY_NOTICES.txt
            runHook postInstall
          '';

          meta = {
            description = "A launcher built for Calamity Client";
            homepage = "https://github.com/tragedy-mc/misfortune-releases";
            license = lib.licenses.unfree;
            sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
            platforms = systems;
            mainProgram = "misfortune";
          };
        };
    in
    {
      packages = eachSystem (pkgs: rec {
        misfortune = mkMisfortune pkgs;
        default = misfortune;
      });

      apps = eachSystem (pkgs: {
        default = {
          type = "app";
          program = lib.getExe self.packages.${pkgs.stdenv.hostPlatform.system}.default;
        };
      });

      overlays.default = final: _prev: {
        misfortune = mkMisfortune final;
      };
    };
}
