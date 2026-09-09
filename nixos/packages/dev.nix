{ pkgs, ... }:
{
  # Build basics + package managers, i.e. the tools that get used interactively outside any
  # project. Not here on purpose: compilers, debuggers, LSP servers and formatters that only
  # ever matter inside one project or one editor - nvim resolves its own (nixvim `extraPackages`,
  # conform/nvim-lint `autoInstall`), VS Code gets them through its FHS env, and project-specific
  # tooling belongs in that project's devShell.
  environment.systemPackages = with pkgs; [
    # Shared with nixvim's rustaceanvim (`rust-toolchain.nix`): the toolchain now carries
    # `bin/rust-analyzer`, so the language server, `cargo` and the proc-macro server are the same
    # release. `nvim` prefixes that same derivation on its PATH (see
    # home-manager/nixvim/modules/plugins/rustaceanvim.nix).
    (import ../../rust-toolchain.nix { inherit pkgs; })

    autoconf
    automake
    cmake
    gcc
    gnumake
    libtool
    ninja
    nixfmt

    pi-coding-agent
    pnpm
    python314
    uv
  ];
}
