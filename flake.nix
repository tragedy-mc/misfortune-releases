{
  description = "Misfortune, a launcher built for Calamity Client (prebuilt release binaries)";

  # The launcher's source is closed. This flake only repackages the binaries
  # published as GitHub releases of this repo; versions and hashes are pinned
  # in ./sources.json, which .github/workflows/update-sources.yml refreshes
  # (via ./update.sh) whenever a release is published.

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

          # Newer releases ship installers (.deb on Linux, .dmg on macOS) that
          # carry the desktop entry, icons and app bundle; older ones only the
          # plain .tar.gz. ./update.sh picks the installer when it exists.
          format =
            if lib.hasSuffix ".deb" platform.asset then
              "deb"
            else if lib.hasSuffix ".dmg" platform.asset then
              "dmg"
            else
              "tarball";

          # Linked directly by the binary.
          linkedLibs = with pkgs; [
            stdenv.cc.cc.lib # libgcc_s
            freetype
            libxcb
            libxkbcommon # also provides libxkbcommon-x11
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

          nativeBuildInputs =
            lib.optionals stdenv.hostPlatform.isLinux [ pkgs.autoPatchelfHook ]
            ++ lib.optionals (format == "deb") [ pkgs.dpkg ]
            ++ lib.optionals (format == "dmg") [
              pkgs.undmg
              pkgs.makeBinaryWrapper
            ];
          buildInputs = lib.optionals stdenv.hostPlatform.isLinux linkedLibs;
          runtimeDependencies = lib.optionals stdenv.hostPlatform.isLinux dlopenLibs;

          sourceRoot = "source";
          unpackPhase = ''
            runHook preUnpack
            mkdir source
          ''
          + {
            # Plain archive: misfortune, LICENSE and THIRD_PARTY_NOTICES.txt, no top-level directory.
            tarball = "tar -xzf $src -C source";
            # cargo-packager .deb: usr/bin, usr/lib/misfortune (resources), usr/share/{applications,icons}.
            deb = "dpkg-deb --fsys-tarfile $src | tar -x -C source --no-same-owner";
            # cargo-packager .dmg (HFS+): Misfortune.app at the image root.
            dmg = "(cd source && undmg $src)";
          }
          .${format}
          + ''

            runHook postUnpack
          '';

          dontConfigure = true;
          dontBuild = true;
          dontStrip = true;

          installPhase = ''
            runHook preInstall
          ''
          + {
            tarball = ''
              install -Dm755 misfortune $out/bin/misfortune
              licenseDir=.
            '';
            deb = ''
              install -Dm755 usr/bin/misfortune $out/bin/misfortune
              mkdir -p $out/share
              cp -r usr/share/applications usr/share/icons $out/share/
              licenseDir=usr/lib/misfortune
            '';
            dmg = ''
              mkdir -p $out/Applications
              cp -R Misfortune.app $out/Applications/
              # A wrapper, not a symlink: launched via a symlink, gpui does not
              # see the app bundle and turns off system notifications.
              makeWrapper $out/Applications/Misfortune.app/Contents/MacOS/misfortune $out/bin/misfortune
              licenseDir=Misfortune.app/Contents/Resources
            '';
          }
          .${format}
          + ''
            install -Dm644 -t $out/share/licenses/misfortune $licenseDir/LICENSE $licenseDir/THIRD_PARTY_NOTICES.txt
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
