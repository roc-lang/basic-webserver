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

        aliases = ''
          alias buildcmd='bash jump-start.sh && roc ./build.roc -- --roc roc'
          alias testcmd='export ROC=roc && export EXAMPLES_DIR=./examples/ && ./ci/all_tests.sh'
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
        ]);
      in {

        devShell = pkgs.mkShell {
          buildInputs = sharedInputs ++ darwinInputs ++ linuxInputs;

          # nix does not store libs in /usr/lib or /lib
          NIX_GLIBC_PATH =
            if pkgs.stdenv.isLinux then "${pkgs.glibc.out}/lib" else "";

          shellHook = ''
            ${aliases}
            
            echo "Some convenient command aliases:"
            echo "${aliases}" | grep -E "alias .*" -o | sed 's/alias /  /' | sed 's/=/ = /'
            echo ""
          '';
        };

        formatter = pkgs.nixpkgs-fmt;
      });
}
