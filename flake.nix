{
  inputs = {
    crane.url = "github:ipetkov/crane?ref=master";
    fenix = {
      url = "github:nix-community/fenix?ref=main";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    flake-utils.url = "github:numtide/flake-utils?ref=main";
    nix-filter.url = "github:numtide/nix-filter?ref=main";
    nixpkgs.url = "github:NixOS/nixpkgs?ref=nixos-unstable";
  };

  outputs = inputs: inputs.flake-utils.lib.eachDefaultSystem (system:
    let
      pkgs = inputs.nixpkgs.legacyPackages.${system};
      stdenv =
        if pkgs.stdenv.isLinux then
          pkgs.stdenvAdapters.useMoldLinker pkgs.stdenv
        else
          pkgs.stdenv;

      mkToolchain = inputs.fenix.packages.${system}.combine;

      toolchain = inputs.fenix.packages.${system}.stable;

      buildToolchain = mkToolchain (with toolchain; [
        cargo
        rustc
      ]);

      devToolchain = mkToolchain (with toolchain; [
        cargo
        clippy
        llvm-tools
        rust-src
        rustc

        # Always use nightly rustfmt because most of its options are unstable
        inputs.fenix.packages.${system}.latest.rustfmt
      ]);

      craneLib = (inputs.crane.mkLib pkgs).overrideToolchain buildToolchain;
      builder = craneLib.buildPackage;
    in
    {
      packages.default = builder {
        src = let filter = inputs.nix-filter.lib; in filter {
          root = ./.;
          include = [
            "Cargo.toml"
            "Cargo.lock"
            "README.md"
            "cargo-progenitor"
            "progenitor"
            "progenitor-client"
            "progenitor-impl"
            "progenitor-macro"
            "example-build" "example-wasm" "example-macro"
          ];
        };
        inherit (craneLib.crateNameFromCargoToml { cargoToml = ./cargo-progenitor/Cargo.toml; }) pname version;
        cargoExtraArgs = "-p cargo-progenitor";
        # TODO: test fails when testing in release mode (default for crane)
        cargoTestCommand = "cargo test";

        stdenv = p: p.stdenv;
      };

      devShells.default = (pkgs.mkShell.override { inherit stdenv; }) {
        env = {
          # Rust Analyzer needs to be able to find the path to default crate
          # sources, and it can read this environment variable to do so. The
          # `rust-src` component is required in order for this to work.
          RUST_SRC_PATH = "${devToolchain}/lib/rustlib/src/rust/library";
        };

        packages = [
          devToolchain
        ] ++ (with pkgs; [
          pkg-config
          openssl
        ]);
      };
    });
}
