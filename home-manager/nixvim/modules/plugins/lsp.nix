{ pkgs, ... }:
# Option values (nixd exprs) come from the shared settings file: Nixvim evaluates its own
# module tree, so HM's extraSpecialArgs stop at nixvim/default.nix (the bridge is `hmConfig`).
let
  inherit (import ../../../../nix/settings.nix) repoPath hostId;
  nixosFlake = ''(builtins.getFlake "${repoPath}")'';
in
{
  # Binaries that LSP servers shell out to *at runtime*, looked up on the nvim process PATH:
  #   nixfmt     - nixd textDocument/formatting (settings.formatting.command)
  #   shellcheck - bash-language-server diagnostics
  #   shfmt      - bash-language-server formatting
  extraPackages = [
    pkgs.nixfmt
    pkgs.shellcheck
    pkgs.shfmt
  ];

  # Signature float while typing; also covers the case where the insert-mode `<C-s>` save
  # mapping shadows Neovim's default `<C-S>` signature help.
  plugins.lsp-signature.enable = true;

  plugins.lsp = {
    enable = true;

    # ---- C / C++ ----
    # clangd takes almost all of its knobs from argv (or a `.clangd` YAML in the repo).
    servers.clangd = {
      enable = true;

      cmd = [
        "clangd"
        # Cross-file completion/goto beyond the single on-demand parsed tree.
        "--background-index"
        # clang-tidy diagnostics *through* clangd; adding `c`/`cpp` -> clangtidy to
        # plugins.lint would publish the same checks twice.
        "--clang-tidy"
        "--completion-style=detailed"
        # No `<algorithm>` appearing in a header you never included.
        "--header-insertion=never"
        # Without this clangd's own formatting falls back to LLVM style, so `<leader>cF`
        # (LSP-only) would reformat projects that have no .clang-format. Note `<leader>cf`
        # prefers conform's clang-format CLI, which has no such switch.
        "--fallback-style=none"
        # `-j` unset: clangd defaults to all cores. Cross-compiling additionally needs
        # "--query-driver=/path/to/g++".
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

    # ---- Nix ----
    # Option docs/completion resolve against the eval of this very flake; home-manager is a
    # NixOS module here (no standalone homeConfigurations), hence the `home-manager.users` hop.
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

    # Keys under `settings` are the server's own; nixvim namespaces most of them (`Lua`,
    # `yaml`, ...) but not all - basedpyright needs the `basedpyright.` prefix by hand.
    servers = {
      # Lua: wezterm's extraConfig, `__raw` blocks in this config, Neovim API analysis.
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

      # Types only; it never formats, so `<leader>cf` still uses conform/ruff.
      # settings left empty on purpose: basedpyright's own default typeCheckingMode is
      # "recommended" (pinning "standard" would *relax* it), and LSP settings beat
      # pyproject.toml outright - per-project strictness belongs in pyproject.toml.
      basedpyright.enable = true;

      # The built-in `ruff server` (>= 0.5.3), not the deprecated `ruff_lsp`: lint + format +
      # autofix with the same rule engine/config discovery as `ruff check` on CI.
      ruff.enable = true;

      jsonls.enable = true; # flake.lock, dashboards/*.json
      yamlls.enable = true; # docker-compose.yml
      marksman.enable = true; # markdown, pairs with render-markdown
      neocmake.enable = true; # CMakeLists.txt + *.cmake
      # Schema-aware completion/diagnostics for every .toml; conform's taplo CLI still wins
      # for formatting (lsp_format = "fallback").
      taplo.enable = true;

      # Fish: deliberately no server. fish_indent (conform) + `fish -n` (lint) + the fish
      # treesitter parser already cover format, syntax errors and highlighting.
    };

    # Parameter names/types from clangd, option info from nixd.
    inlayHints = true;

    # Buffer-local keymaps, registered on `LspAttach`. Neovim's own defaults already cover
    # hover (`K`), `gra`/`grn`/`grr`/`gri`/`grt`/`grx` and `gO` (:help lsp-defaults).
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
