{
  description = "ghidra-cli — Rust CLI for Ghidra reverse engineering with AI agent support";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    rust-overlay.url = "github:oxalica/rust-overlay";
    rust-overlay.inputs.nixpkgs.follows = "nixpkgs";
    crane.url = "github:ipetkov/crane";
  };

  outputs = { self, nixpkgs, flake-utils, rust-overlay, crane }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          overlays = [ rust-overlay.overlays.default ];
        };

        rustToolchain = pkgs.rust-bin.stable.latest.default;
        craneLib = (crane.mkLib pkgs).overrideToolchain rustToolchain;

        src = pkgs.lib.cleanSourceWith {
          src = ./.;
          filter = path: type:
            (craneLib.filterCargoSources path type)
            || (builtins.match ".*\.java$" path != null)
            || (builtins.match ".*\.pest$" path != null);
        };

        commonArgs = {
          inherit src;
          pname = "ghidra-cli";
          version = "0.1.10";
          strictDeps = true;
          nativeBuildInputs = with pkgs; [ pkg-config ];
          buildInputs = with pkgs; [ openssl ]
            ++ pkgs.lib.optionals pkgs.stdenv.hostPlatform.isDarwin [
              pkgs.darwin.apple_sdk.frameworks.Security
              pkgs.darwin.apple_sdk.frameworks.SystemConfiguration
            ];
        };

        cargoArtifacts = craneLib.buildDepsOnly commonArgs;

        ghidra-cli = craneLib.buildPackage (commonArgs // {
          inherit cargoArtifacts;
          doCheck = false;
          # Wrap the binary so GHIDRA_INSTALL_DIR is set when ghidra is available
          postInstall = ''
            mv $out/bin/ghidra $out/bin/.ghidra-cli-unwrapped
            cat > $out/bin/ghidra-cli <<WRAPPER
            #!/bin/sh
            # Auto-detect GHIDRA_INSTALL_DIR from ghidra on PATH if not set
            if [ -z "\$GHIDRA_INSTALL_DIR" ]; then
              GHIDRA_BIN="\$(command -v ghidraRun 2>/dev/null || command -v analyzeHeadless 2>/dev/null || true)"
              if [ -n "\$GHIDRA_BIN" ]; then
                GHIDRA_BIN="\$(readlink -f "\$GHIDRA_BIN")"
                export GHIDRA_INSTALL_DIR="\$(dirname "\$(dirname "\$GHIDRA_BIN")")"
              fi
            fi
            exec "$out/bin/.ghidra-cli-unwrapped" "\$@"
            WRAPPER
            chmod +x $out/bin/ghidra-cli
          '';
        });
      in
      {
        packages = {
          default = ghidra-cli;
          ghidra-cli = ghidra-cli;
        };

        devShells.default = pkgs.mkShell {
          packages = [
            rustToolchain
            pkgs.pkg-config
            pkgs.openssl
          ];
        };

      }
    ) // {
      # Overlay for use in other flakes (system-independent)
      overlays.default = final: prev: {
        ghidra-cli = self.packages.${prev.stdenv.hostPlatform.system}.ghidra-cli;
      };
    };
}
