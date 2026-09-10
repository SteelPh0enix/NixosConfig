{
  description = "My NixOS configuration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

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

    # Externally managed checkout (updated by the `llama-cpp-update` script).
    # Deliberately unpinned: the working tree *is* the input, `nix flake update llama-cpp` is a no-op.
    # Literal path required here - flake input URLs are read syntactically. Keep in sync with
    # settings.llamaCppPath.
    llama-cpp.url = "path:/home/steelph0enix/llama.cpp";

    nix-cachyos-kernel.url = "github:xddxdd/nix-cachyos-kernel";

    nixvim = {
      url = "github:nix-community/nixvim";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    openlogi = {
      url = "github:AprilNEA/OpenLogi";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Licensed, non-redistributable font files kept outside this repo (mode 700), consumed by
    # home-manager/nonfree-fonts.nix. Refresh with `nix flake update berkeleyMono`.
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
      nixvim,
      openlogi,
      ...
    }@inputs:
    let
      settings = import ./nix/settings.nix;
      # settings.hostId is also networking.hostName, which is what `nh os` autodetects.
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
            openlogi.nixosModules.default
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

      # Same toolchain as the system profile and VS Code's FHS environment; `:NixDevelop` in
      # Neovim loads this shell.
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
