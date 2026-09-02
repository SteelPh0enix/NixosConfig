{ ... }:
{
  # ---- nix-develop ----
  # Run `nix develop` inside the running Neovim instead of restarting nvim from a devshell,
  # so the LSP servers inherit the shell environment (LIBCLANG_PATH, CARGO_TARGET_DIR,
  # PYTHONPATH, ...). Commands (figsoda/nix-develop.nvim):
  #   :NixDevelop              # the flake devShell of the cwd
  #   :NixDevelop .#foo        # a specific flake target
  #   :NixDevelop --impure
  #   :NixShell nixpkgs#hello  # any `nix shell` target
  #
  # Clients capture their environment when they *spawn*, so after loading a shell restart the
  # ones that matter: `<leader>lR` (`:lsp restart`, see plugins/lsp.nix).
  #
  # Defaults kept: `ignoredVariables` (HOME, TERM, ... must not be re-applied to a running
  # editor) and `separatedVariables` (PATH/XDG_DATA_DIRS are joined, not replaced). Add e.g.
  #   separatedVariables.LUA_PATH = ":";
  # if a devshell needs another colon-separated var merged.
  plugins.nix-develop.enable = true;
}
