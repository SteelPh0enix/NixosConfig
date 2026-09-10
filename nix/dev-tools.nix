# Build tools shared by the system profile, VS Code's FHS environment and `nix develop`.
# Anything language-server-specific stays with its consumer.
pkgs: with pkgs; [
  autoconf
  automake
  cmake
  gcc
  gnumake
  libtool
  ninja
  nixfmt
  uv
]
