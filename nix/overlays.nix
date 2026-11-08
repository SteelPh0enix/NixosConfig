# Overlays shared by the system (`nixpkgs.overlays`) and the flake devShell.
inputs: [
  inputs.llama-cpp.overlays.default
  (import ./overlays/flashpoint.nix)
  (import ./overlays/llama-cpp.nix)
  (import ./overlays/ltrace.nix)
  (import ./overlays/phonto.nix inputs)
]
