{
  description = "My NixOS configuration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    # The kernel alone comes from the stable release: unstable's linux-zen 7.3.4-zen1 has the
    # duplicated `current_at` store that panics in a BH worker on boot (zen-kernel#425, fixed in
    # -zen2), while 7.2.15-zen1 does not. Deliberately does not follow `nixpkgs`.
    nixpkgs-stable.url = "github:NixOS/nixpkgs/nixos-26.05";

    home-manager.url = "github:nix-community/home-manager/master";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";

    nix-index-database.url = "github:nix-community/nix-index-database";
    nix-index-database.inputs.nixpkgs.follows = "nixpkgs";

    ucodenix = {
      url = "github:e-tho/ucodenix";
    };

    # Deliberately unpinned: the working tree *is* the input. Literal path, and kept in sync with
    # settings.llamaCppPath, because flake input URLs are read syntactically.
    llama-cpp.url = "path:/home/steelph0enix/llama.cpp";

    nixvim = {
      url = "github:nix-community/nixvim";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    pi.url = "github:earendil-works/pi/stable";

    # oh-my-pi (`omp`), a pi fork, installed beside pi. Do not make its nixpkgs follow ours: it
    # builds against its own bun2nix/rust pin. Its rust-overlay lock trails the nightly its
    # `rust-toolchain.toml` names, so the revision is pinned too (2026-11-08) - bump it when that
    # nightly moves.
    omp = {
      url = "github:can1357/oh-my-pi";
      inputs.rust-overlay = {
        url = "github:oxalica/rust-overlay/51c6dc40d18552701f7c5c62e3f7a5fc899f7132";
        inputs.nixpkgs.follows = "omp/nixpkgs";
      };
    };

    berkeleyMono = {
      url = "path:/home/steelph0enix/nixos-nonfree/berkeley-mono";
      flake = false;
    };
  };

  outputs =
    {
      nixpkgs,
      home-manager,
      nix-index-database,
      ...
    }@inputs:
    let
      settings = import ./nix/settings.nix;
      inherit (settings) hostId;
    in
    {
      nixosConfigurations = {
        ${hostId} = nixpkgs.lib.nixosSystem {
          specialArgs = {
            inherit
              inputs
              settings
              ;
          };
          modules = [
            ./nixos/configuration.nix
            nix-index-database.nixosModules.nix-index
            home-manager.nixosModules.home-manager
            {
              home-manager.backupFileExtension = "hmgr.backup";
              home-manager.useGlobalPkgs = true;
              home-manager.useUserPackages = true;
              home-manager.extraSpecialArgs = inputs // {
                inherit settings;
              };
              home-manager.users.${settings.userName} = import ./home-manager/home.nix;
            }
          ];
        };
      };

      devShells.x86_64-linux.default =
        let
          pkgs = import nixpkgs {
            system = "x86_64-linux";
            config = import ./nix/nixpkgs-config.nix;
            overlays = import ./nix/overlays.nix inputs;
          };
        in
        pkgs.mkShellNoCC {
          packages = import ./nix/dev-tools.nix pkgs ++ [
            pkgs.nixd
            pkgs.nix-index
            pkgs.shellcheck
            pkgs.shfmt
            pkgs.statix
            pkgs.deadnix
          ];
        };
    };
}
