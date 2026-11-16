{ lib, ... }:
{
  # External linters for the gaps LSP leaves open; `autoInstall` puts them on the wrapper PATH.
  # `mkForce` because nixvim's own `lintersByFt` defaults would drag vale, jsonlint, hadolint
  # and friends into the closure. shellcheck, ruff and clang-tidy stay out: the LSP servers
  # above already publish those, so handing one back here means disabling it there first.
  plugins.lint = {
    enable = true;
    autoInstall.enable = true;

    lintersByFt = lib.mkForce {
      fish = [ "fish" ]; # `fish -n` syntax check - no fish LSP enabled
      nix = [
        "statix"
        "deadnix"
      ]; # nixd only reports parse/semantic errors
    };

    # Lint on `:w`; `linters = null` for manual-only linting.
  };
}
