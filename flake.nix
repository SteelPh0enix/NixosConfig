{
  description = "My NixOS configuration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";

    home-manager.url = "github:nix-community/home-manager/release-25.05";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
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
      inherit (self) outputs;
    in
    {
      nixosConfigurations = {
        steelph0enix-pc =
          let
            username = "steelph0enix";
            specialArgs = { inherit username inputs outputs; };
          in
          nixpkgs.lib.nixosSystem {
            inherit specialArgs;
            system = "x86_64-linux";
            pkgs.overlays = [ (import ./overlays/llamacpp.nix) ];
            modules = [
              ./nixos/configuration.nix

              home-manager.nixosModules.home-manager
              {
                home-manager.useGlobalPkgs = true;
                home-manager.useUserPackages = true;
                home-manager.extraSpecialArgs = inputs // specialArgs;
                home-manager.users.${username} = import ./home-manager/home.nix;
              }
            ];
          };
      };
    };
}
