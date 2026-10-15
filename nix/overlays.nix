# Overlays shared by the system (`nixpkgs.overlays`) and the flake devShell.
inputs: [
  inputs.rust-overlay.overlays.default
  inputs.llama-cpp.overlays.default
  (import ./overlays/llama-cpp.nix)
  # gufo ships packages, not an overlay; expose its release build as pkgs.gufo.
  (final: _prev: {
    gufo = inputs.gufo.packages.${final.system}.release;
  })
  (import ./overlays/ltrace.nix)
  (import ./overlays/rust-toolchain.nix)
]
