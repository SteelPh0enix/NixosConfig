{
  description = "My NixOS configuration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";

    home-manager.url = "github:nix-community/home-manager/release-25.11";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";

    nix-index-database.url = "github:nix-community/nix-index-database";
    nix-index-database.inputs.nixpkgs.follows = "nixpkgs";

    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nix-ai-tools.url = "github:numtide/nix-ai-tools";
    ucodenix.url = "github:e-tho/ucodenix";
    llama-cpp.url = "path:/home/steelph0enix/llama.cpp";

    compose2nix.url = "github:aksiksi/compose2nix";
    compose2nix.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs =
    {
      self,
      nixpkgs,
      nixpkgs-unstable,
      home-manager,
      nix-index-database,
      llama-cpp,
      ...
    }@inputs:
    let
      inherit (self) outputs;
      system = "x86_64-linux";

      # Single definition of pkgsUnstable with all overlays
      pkgsUnstable = import nixpkgs-unstable {
        inherit system;
        overlays = [
          (import ./nixos/overlays/rocm.nix)
          llama-cpp.overlays.default
          (import ./nixos/overlays/llama-cpp.nix)
        ];
        config.allowUnfree = true;
        config.rocmSupport = false;
      };

      specialArgs = {
        inherit
          inputs
          outputs
          pkgsUnstable
          system
          ;
      };
    in
    {
      nixosConfigurations = {
        RX-78-FPC = nixpkgs.lib.nixosSystem {
          inherit specialArgs;
          modules = [
            { _module.args = inputs; }
            ./nixos/configuration.nix
            nix-index-database.nixosModules.nix-index
            home-manager.nixosModules.home-manager
            {
              home-manager.backupFileExtension = "hmgr.backup";
              home-manager.useGlobalPkgs = true;
              home-manager.useUserPackages = true;
              home-manager.extraSpecialArgs = inputs // specialArgs;
              home-manager.users.steelph0enix = import ./home-manager/home.nix;
            }
          ];
        };
      };
    };
}
