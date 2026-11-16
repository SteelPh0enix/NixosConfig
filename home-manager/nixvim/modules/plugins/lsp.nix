{ pkgs, ... }:
# The nixd exprs come from the shared settings file: nixvim evaluates its own module tree, so
# home-manager's extraSpecialArgs stop at nixvim/default.nix.
let
  inherit (import ../../../../nix/settings.nix) repoPath hostId;
  nixosFlake = ''(builtins.getFlake "${repoPath}")'';
in
{
  # Runtime dependencies of the servers, looked up on nvim's PATH: nixfmt for nixd,
  # shellcheck and shfmt for bashls.
  extraPackages = [
    pkgs.nixfmt
    pkgs.shellcheck
    pkgs.shfmt
  ];

  plugins.lsp-signature.enable = true;

  plugins.lsp = {
    enable = true;

    # clangd takes its knobs from argv or a `.clangd` in the repo.
    servers.clangd = {
      enable = true;

      cmd = [
        "clangd"
        "--background-index"
        # Through clangd; a clangtidy entry in plugins.lint would publish these checks twice.
        "--clang-tidy"
        "--completion-style=detailed"
        # No `<algorithm>` appearing in a header you never included.
        "--header-insertion=never"
        # Otherwise clangd formats in LLVM style, so `<leader>cF` would reformat projects that
        # carry no .clang-format.
        "--fallback-style=none"
      ];

      # Root = where the compilation database lives. `rootMarkers` REPLACES the list (a list
      # key is overwritten, not merged), so this is the full set rather than an addition.
      rootMarkers = [
        "compile_commands.json"
        "compile_flags.txt"
        ".clangd"
        ".clang-tidy"
        ".clang-format"
        "configure.ac"
        ".git" # last: single .c files inside a repo still get a stable root
      ];
    };

    # Option docs resolve against the eval of this flake; home-manager is a NixOS module here,
    # hence the `home-manager.users` hop.
    servers.nixd = {
      enable = true;

      settings = {
        nixpkgs.expr = "${nixosFlake}.inputs.nixpkgs { }";

        options = {
          nixos.expr = "${nixosFlake}.nixosConfigurations.\"${hostId}\".options";
          "home-manager".expr =
            "${nixosFlake}.nixosConfigurations.\"${hostId}\".options.home-manager.users.type.getSubOptions []";
        };

        formatting.command = [ "nixfmt" ];
      };
    };

    # Keys under `settings` are the server's own; nixvim namespaces most, but basedpyright needs
    # its `basedpyright.` prefix by hand.
    servers = {
      lua_ls = {
        enable = true;
        settings = {
          runtime.version = "LuaJIT";
          diagnostics.globals = [ "vim" ];
          workspace = {
            checkThirdParty = false;
            library.__raw = "vim.api.nvim_get_runtime_file('', true)";
          };
          telemetry.enable = false;
        };
      };

      bashls.enable = true;

      # Types only. Settings left empty on purpose: the default typeCheckingMode is "recommended"
      # (pinning "standard" would relax it), and LSP settings beat pyproject.toml.
      basedpyright.enable = true;

      # The built-in `ruff server` (>= 0.5.3), not the deprecated `ruff_lsp`.
      ruff.enable = true;

      jsonls.enable = true;
      yamlls.enable = true;
      marksman.enable = true;
      # Re-enable once nixpkgs gives neocmakelsp pkg-config/oniguruma: its rust hook sets
      # RUSTONIG_SYSTEM_LIBONIG and the build fails without them.
      neocmake.enable = false;
      # conform's taplo CLI still wins for formatting (lsp_format = "fallback").
      taplo.enable = true;

      # Fish: deliberately no server - fish_indent, `fish -n` and treesitter already cover it.
    };

    inlayHints = true;

    keymaps = {
      lspBuf = {
        "gd" = "definition";
        "gD" = "declaration";
      };

      # lspconfig's `:LspStart`/`:LspStop` do not exist on Nvim >= 0.11, so these use core's
      # `:lsp` subcommands. `:lsp enable` is deliberately unmapped: without a server name it also
      # attaches Neovim's built-in configs (it pulled nil_ls into a Nix buffer).
      extra = [
        {
          key = "<leader>ch";
          action = "<Cmd>LspClangdSwitchSourceHeader<CR>";
          options.desc = "Switch source/header (clangd buffers only)";
        }
        {
          key = "<leader>ls";
          action = "<Cmd>doautocmd FileType<CR>";
          options.desc = "Attach LSP servers to this buffer";
        }
        {
          key = "<leader>lx";
          action = "<Cmd>lsp stop<CR>";
          options.desc = "Stop LSP clients of this buffer";
        }
        {
          key = "<leader>lR";
          action = "<Cmd>lsp restart<CR>";
          options.desc = "Restart LSP clients of this buffer";
        }
      ];
    };
  };
}
