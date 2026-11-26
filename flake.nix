{
  description = "My NixOS configuration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    home-manager.url = "github:nix-community/home-manager/master";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";

    nix-index-database.url = "github:nix-community/nix-index-database";
    nix-index-database.inputs.nixpkgs.follows = "nixpkgs";

    ucodenix = {
      url = "github:e-tho/ucodenix";
    };

    # Externally managed checkout, re-pinned by `llama-cpp-update`. Input URLs must be literal,
    # so this repeats settings.llamaCppPath.
    llama-cpp.url = "path:/home/steelph0enix/llama.cpp";

    nixvim = {
      url = "github:nix-community/nixvim";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # pi coding agent, packages only; no binary cache.
    pi.url = "github:earendil-works/pi/stable";

    # Gufo engine for Strix Halo; nix/overlays.nix maps `release` onto pkgs.gufo. No binary cache.
    gufo.url = "github:gufo-org/gufo";

    # oh-my-pi (`omp`), a pi fork; omp reads and writes only ~/.omp. Do not make its nixpkgs follow
    # ours: it builds against its own pin. Keep the rust-overlay revision in step with its
    # `rust-toolchain.toml`.
    omp = {
      url = "github:can1357/oh-my-pi";
      inputs.rust-overlay = {
        url = "github:oxalica/rust-overlay/51c6dc40d18552701f7c5c62e3f7a5fc899f7132";
        inputs.nixpkgs.follows = "omp/nixpkgs";
      };
    };

    # Licensed, non-redistributable fonts kept outside this repo, consumed by
    # home-manager/nonfree-fonts.nix.
    berkeleyMono = {
      url = "path:/home/steelph0enix/nixos-nonfree/berkeley-mono";
      flake = false;
    };

    # Disco Elysium skills pack for omp, pulled from GitHub: a git submodule would be an
    # empty dir in this flake's own store source. Source-only input (the repo has no
    # flake.nix); consumed as ${disco-elysium-skills}/.omp in home-manager/omp.
    disco-elysium-skills = {
      url = "github:SteelPh0enix/DiscoElysiumSkills";
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

      # Same toolchain as the system profile and VS Code's FHS environment.
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
