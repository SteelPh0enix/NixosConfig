{ pkgs, ... }:
{
  environment.systemPackages = with pkgs; [
    zenity
    btop-rocm
    nerd-font-patcher
    sqlite
    openscad-unstable
    openscad-lsp
  ];
}
