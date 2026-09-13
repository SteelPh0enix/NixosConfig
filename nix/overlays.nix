# Overlays shared by the system (`nixpkgs.overlays`) and the flake devShell.
inputs: [
  inputs.rust-overlay.overlays.default
  inputs.nix-cachyos-kernel.overlays.pinned
  inputs.llama-cpp.overlays.default
  (import ./overlays/llama-cpp.nix)
  (import ./overlays/rust-toolchain.nix)
]
