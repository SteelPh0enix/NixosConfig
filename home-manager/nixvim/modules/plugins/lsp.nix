{ pkgs, ... }:
# nixd option exprs come from the shared settings; Nixvim evaluates its own module tree.
let
  inherit (import ../../../../nix/settings.nix) repoPath hostId;
  nixosFlake = ''(builtins.getFlake "${repoPath}")'';
in
{
  # Binaries the LSP servers shell out to at runtime.
  extraPackages = [
    pkgs.nixfmt
    pkgs.shellcheck
    pkgs.shfmt
  ];

  # Also covers the insert-mode `<C-s>` save map shadowing the default signature help.
  plugins.lsp-signature.enable = true;

  plugins.lsp = {
    enable = true;

    # clangd takes its knobs from argv or a `.clangd` file.
    servers.clangd = {
      enable = true;

      cmd = [
        "clangd"
        "--background-index"
        # clang-tidy through clangd; lint.nix must not repeat the same checks.
        "--clang-tidy"
        "--completion-style=detailed"
        "--header-insertion=never"
        # Without it clangd falls back to LLVM style and `<leader>cF` would reformat projects.
        "--fallback-style=none"
      ];

      # `rootMarkers` replaces the list, it does not merge.
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

    # Option docs resolve against this flake's eval; home-manager is a NixOS module here.
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

    # `settings` keys are the server's own; basedpyright needs its prefix by hand.
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

      bashls.enable = true; # shellcheck/shfmt come from extraPackages

      # basedpyright's default typeCheckingMode is "recommended"; LSP settings beat
      # pyproject.toml, so per-project strictness belongs there.
      basedpyright.enable = true;

      # The built-in `ruff server`, not the deprecated `ruff_lsp`.
      ruff.enable = true;

      jsonls.enable = true; # flake.lock, dashboards/*.json
      yamlls.enable = true; # docker-compose.yml
      marksman.enable = true; # markdown, pairs with render-markdown
      # conform's taplo CLI still does the formatting.
      taplo.enable = true;

      # No fish server: fish_indent + `fish -n` + treesitter already cover it.
    };

    inlayHints = true;

    # Buffer-local keymaps; Neovim's own defaults already cover `K`, `gr*` and `gO`.
    keymaps = {
      lspBuf = {
        "gd" = "definition";
        "gD" = "declaration";
      };

      # Anything that is not a plain `vim.lsp.buf` call. lspconfig's `:LspStart`/`:LspStop`
      # don't exist on Nvim >= 0.11, so these use core's `:lsp` subcommands (:help :lsp-enable).
      # `:lsp enable` is deliberately unmapped: without a server name it also attaches
      # Neovim's built-in configs (bare `:lsp enable` attached nil_ls in a Nix buffer).
      # Re-attaching after a stop is just a FileType reload (<leader>ls).
      extra = [
        {
          # clangd's private switchSourceHeader request; lspconfig's clangd.lua registers the
          # command in its on_attach, so no extra plugin is needed. Buffer-local, so it E492s
          # where clangd is not the client.
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
