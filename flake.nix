{
  description = "basic-webserver devShell flake";

  inputs = {
    roc.url = "github:roc-lang/roc";

    nixpkgs.follows = "roc/nixpkgs";

    # rust from nixpkgs has some libc problems, this is patched in the rust-overlay
    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # to easily make configs for multiple architectures
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, roc, rust-overlay, flake-utils }:
    let supportedSystems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
    in flake-utils.lib.eachSystem supportedSystems (system:
      let
        overlays = [ (import rust-overlay) ];
        pkgs = import nixpkgs { inherit system overlays; };
        rocPkgs = roc.packages.${system};

        llvmPkgs = pkgs.llvmPackages_16;

        rust =
          pkgs.rust-bin.fromRustupToolchainFile "${toString ./rust-toolchain.toml}";

        shellFunctions = ''
          buildcmd() {
            bash jump-start.sh && roc ./build.roc -- --roc roc "$@"
          }
          export -f buildcmd

          testcmd() {
            export EXAMPLES_DIR=./examples/ && ./ci/all_tests.sh "$@"
          }
          export -f testcmd
        '';

        linuxInputs = with pkgs;
          lib.optionals stdenv.isLinux [
            valgrind # for debugging
          ];

        darwinInputs = with pkgs;
          lib.optionals stdenv.isDarwin
          (with pkgs.darwin.apple_sdk.frameworks; [
            Security
          ]);

        sharedInputs = (with pkgs; [
          rust
          llvmPkgs.clang
          expect
          rocPkgs.cli
          sqlite
          nmap # ncat server for tests
          ripgrep # for ci/check_all_exposed_funs_tested.roc
        ]);
      in {

        devShell = pkgs.mkShell {
          buildInputs = sharedInputs ++ darwinInputs ++ linuxInputs;

          # nix does not store libs in /usr/lib or /lib
          NIX_GLIBC_PATH =
            if pkgs.stdenv.isLinux then "${pkgs.glibc.out}/lib" else "";

          shellHook = ''
            export ROC=roc

            ${shellFunctions}
            
            echo "Some convenient commands:"
            echo "${shellFunctions}" | grep -E '^\s*[a-zA-Z_][a-zA-Z0-9_]*\(\)' | sed 's/().*//' | sed 's/^[[:space:]]*/  /' | while read func; do
              body=$(echo "${shellFunctions}" | sed -n "/''${func}()/,/^[[:space:]]*}/p" | sed '1d;$d' | tr '\n' ';' | sed 's/;$//' | sed 's/[[:space:]]*$//')
              echo "  $func = $body"
            done
            echo ""
          '';
        };

        formatter = pkgs.nixpkgs-fmt;
      });
}
