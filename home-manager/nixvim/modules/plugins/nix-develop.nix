{ ... }:
{
  # Run `nix develop` inside the running Neovim (`:NixDevelop`, `:NixShell <installable>`) so
  # LSP servers inherit the devshell environment. Clients capture their environment at spawn,
  # so restart them afterwards with `<leader>lR`.
  plugins.nix-develop.enable = true;
}
