_: {
  # Runs `nix develop` inside Neovim so LSP servers inherit the devshell. Clients capture
  # their environment at spawn, so restart them with `<leader>lR`.
  plugins.nix-develop.enable = true;
}
