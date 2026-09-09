{ lib, config, ... }:
{
  options.my = {
    nixosConfigRepoPath = lib.mkOption {
      type = lib.types.str;
      default = "${config.home.homeDirectory}/nixos-config";
      description = "Path to this flake checkout.";
    };

    llamaCppRepoPath = lib.mkOption {
      type = lib.types.str;
      default = "${config.home.homeDirectory}/llama.cpp";
      description = ''
        Externally managed llama.cpp checkout: the `llama-cpp` flake input (flake.nix)
        and the target of the `llama-cpp-update` shell function.
      '';
    };
  };
}
