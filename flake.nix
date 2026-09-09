{
  description = "My NixOS configuration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    # Pinned fallback for packages whose current build is unusable (see nixos/services/samba.nix).
    nixpkgs-previous.url = "github:NixOS/nixpkgs/d407951447dcd00442e97087bf374aad70c04cea";

    home-manager.url = "github:nix-community/home-manager/master";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";

    nix-index-database.url = "github:nix-community/nix-index-database";
    nix-index-database.inputs.nixpkgs.follows = "nixpkgs";

    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    ucodenix = {
      url = "github:e-tho/ucodenix";
    };

    # Externally managed checkout (updated by `llama-cpp-update`, see home-manager/shell.nix).
    # Deliberately unpinned: the working tree *is* the input, `nix flake update llama-cpp` is a no-op.
    llama-cpp.url = "path:/home/steelph0enix/llama.cpp";

    compose2nix = {
      url = "github:aksiksi/compose2nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nix-cachyos-kernel.url = "github:xddxdd/nix-cachyos-kernel";

    nixvim = {
      url = "github:nix-community/nixvim";
      inputs.nixpkgs.follows = "nixpkgs";
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
      # Single source of truth: the flake output name, networking.hostName, and therefore
      # what `nh os` auto-detects as --hostname.
      hostId = "RX-78-FPC";
    in
    {
      nixosConfigurations = {
        ${hostId} = nixpkgs.lib.nixosSystem {
          specialArgs = {
            inherit inputs hostId;
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
                inherit hostId;
              };
              home-manager.users.steelph0enix = import ./home-manager/home.nix;
            }
          ];
        };
      };
    };
}
