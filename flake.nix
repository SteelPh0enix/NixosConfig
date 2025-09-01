{
  description = "My NixOS configuration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";

    home-manager.url = "github:nix-community/home-manager/release-25.05";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";

    nix-ai-tools.url = "github:numtide/nix-ai-tools";
  };

  outputs =
    {
      self,
      nixpkgs,
      nixpkgs-unstable,
      home-manager,
      ...
    }@inputs:
    let
      system = "x86_64-linux";
      inherit (self) outputs;
    in
    {
      nixosConfigurations = {
        steelph0enix-work-vm =
          let
            specialArgs = {
              inherit
                inputs
                outputs
                ;

              pkgsUnstable = import nixpkgs-unstable {
                inherit system;
                config.allowUnfree = true;
              };
            };
          in
          nixpkgs.lib.nixosSystem {
            inherit specialArgs system;
            modules = [
              ./nixos/configuration.nix
              home-manager.nixosModules.home-manager
              {
                home-manager.backupFileExtension = ".hmgr.backup";
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
