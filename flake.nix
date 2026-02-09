{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    lute-src = {
      url = "github:luau-lang/lute";
      flake = false;
    };
  };

  outputs = {
    self,
    nixpkgs,
    lute-src,
    ...
  }: let
    inherit (nixpkgs) lib;

    forAllSystems = f:
      lib.genAttrs lib.systems.flakeExposed (system: f nixpkgs.legacyPackages.${system});
  in {
    packages = forAllSystems (pkgs: let
      deps = builtins.fromJSON (builtins.readFile ./deps.json);
      extern = lib.listToAttrs (map (dep: {
        name = dep.name;
        value = pkgs.fetchgit {
          url = dep.url;
          rev = dep.revision;
          sha256 = dep.sha256;
          fetchSubmodules = false;
        };
      }) deps);

      copyExterns = lib.concatStringsSep "\n" (lib.mapAttrsToList (name: path: ''
        cp -R --no-preserve=mode ${path} extern/${name}
      '') extern);
    in {
      default = pkgs.llvmPackages_18.libcxxStdenv.mkDerivation {
        pname = "lute";
        version = "0.1.0";

        src = lute-src;

        nativeBuildInputs = with pkgs; [
          cmake
          ninja
          git
        ];

        dontConfigure = true;

        buildPhase = ''
          runHook preBuild

          ${copyExterns}

          mkdir -p lute/std/src/generated
          cp tools/templates/std_impl.cpp lute/std/src/generated/modules.cpp
          cp tools/templates/std_header.h lute/std/src/generated/modules.h

          mkdir -p lute/cli/generated
          cp tools/templates/cli_impl.cpp lute/cli/generated/commands.cpp
          cp tools/templates/cli_header.h lute/cli/generated/commands.h

          cmake -G Ninja -B build/debug -DCMAKE_BUILD_TYPE=Debug
          ninja -C build/debug lute/cli/lute

          mv build/debug/lute/cli/lute build/lute0

          # Precompute the tune hash so luthier won't fetch deps.
          mkdir -p extern/generated
          tmp_hash_input="$(mktemp)"
          LC_ALL=C find extern -maxdepth 1 -type f -name '*.tune' -printf '%f\n' | sort | while read -r name; do
            printf "%s" "$name" >> "$tmp_hash_input"
            cat "extern/$name" >> "$tmp_hash_input"
          done
          tune_hash="$(b2sum --length=256 "$tmp_hash_input" | cut -d' ' -f1)"
          printf "%s" "$tune_hash" > extern/generated/hash.txt
          rm -f "$tmp_hash_input"

          build/lute0 tools/luthier.luau configure --config release --clean lute
          build/lute0 tools/luthier.luau build --config release --clean lute

          runHook postBuild
        '';

        installPhase = ''
          runHook preInstall

          mkdir -p $out/bin
          cp build/release/lute/cli/lute $out/bin/lute

          runHook postInstall
        '';

        checkPhase = ''
          runHook preCheck

          export HOME="$TMPDIR"
          ninja -C build/release tests/lute-tests
          ./build/release/tests/lute-tests

          runHook postCheck
        '';

        doCheck = false;
      };
    });

    checks = lib.genAttrs lib.systems.flakeExposed (system: {
      lute-tests = self.packages.${system}.default.overrideAttrs (old: {
        doCheck = true;
      });
    });

    apps = forAllSystems (pkgs: {
      update-deps = {
        type = "app";
        meta = {
          description = "A script which fetches lute dep hashes";
        };
        program = toString (pkgs.writeShellScript "update-deps" ''
          export PATH="${lib.makeBinPath [ pkgs.nushell pkgs.nix-prefetch-git ]}:$PATH"
          exec nu ${./update-deps.nu} --lute-path ${lute-src} --out deps.json
        '');
      };
    });
  };
}
