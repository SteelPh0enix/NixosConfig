{ lib, ... }:
{
  # External linters for the gaps LSP leaves open. `autoInstall` resolves each name to a nix
  # package and puts it on the nvim wrapper PATH.
  #
  # `lintersByFt` has nixvim defaults (vale, jsonlint, hadolint, tflint, ...) that autoInstall
  # would drag into the closure, hence `mkForce` instead of adding keys.
  #
  # Deliberately absent, because the LSP already publishes the same diagnostics:
  #   sh/bash -> shellcheck (bash-language-server finds it on PATH)
  #   python  -> ruff (plugins.lsp.servers.ruff runs the same rule engine, on-change)
  #   c/cpp   -> clang-tidy (clangd starts with --clang-tidy)
  # To hand one back to nvim-lint: disable the server side and re-add it below.
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

    # Lint on `:w` (nixvim's BufWritePost default); `linters = null` for manual-only linting.
  };
}
