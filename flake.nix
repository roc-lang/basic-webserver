{
  description = "basic-webserver devShell flake";

  inputs = {

    # This commit is for the builtin-task branch, remove after it is merged into main
    roc.url = "github:roc/roc?rev=6db429ff17b66a1ebe62e79f099d82fad6704d9d";

    nixpkgs.follows = "roc/nixpkgs";

    # rust from nixpkgs has some libc problems, this is patched in the rust-overlay
    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-utils.follows = "flake-utils";
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
        };

        formatter = pkgs.nixpkgs-fmt;
      });
}
