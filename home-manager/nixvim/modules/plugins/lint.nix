{ lib, ... }:
{
  # External linters for gaps the LSP leaves; `autoInstall` puts each on the wrapper PATH.
  # `mkForce` drops nixvim's defaults so they stay out of the closure.
  # Absent because the LSP already publishes the same diagnostics: shellcheck (bashls),
  # ruff (plugins.lsp.ruff), clang-tidy (clangd).
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
  };
}
