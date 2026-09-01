{ pkgs, ... }:
{
  # ---- LSP ----

  # nixd calls this through the LSP `textDocument/formatting` request.
  extraPackages = [ pkgs.nixfmt ];

  # Signature float while typing arguments. Also covers the case where the
  # insert-mode `<C-s>` save mapping shadows Neovim's default `<C-S>` signature help.
  plugins.lsp-signature.enable = true;

  plugins.lsp = {
    enable = true;

    servers.clangd.enable = true;

    # Nix. Option docs/completion are resolved against the eval of this very flake;
    # home-manager is wired in as a NixOS module here (no standalone
    # homeConfigurations output), hence the `home-manager.users` hop.
    servers.nixd = {
      enable = true;
      # nixvim nests these under the `nixd` key itself, so the keys below are the
      # ones from nixd's own configuration docs. Note the hyphen in "home-manager".
      settings = {
        # Package/lib completion against the nixpkgs this flake pins.
        nixpkgs.expr = ''(builtins.getFlake "/home/steelph0enix/nixos-config").inputs.nixpkgs { }'';

        options = {
          nixos.expr = ''(builtins.getFlake "/home/steelph0enix/nixos-config").nixosConfigurations."RX-78-FPC".options'';

          # home-manager is wired in as a NixOS module (no standalone
          # homeConfigurations output), so its declarations come from the
          # `home-manager.users` submodule of the system config.
          "home-manager".expr =
            ''(builtins.getFlake "/home/steelph0enix/nixos-config").nixosConfigurations."RX-78-FPC".options.home-manager.users.type.getSubOptions []'';
        };

        formatting.command = [ "nixfmt" ];
      };
    };

    # The rest of the languages this repo is written in. Keys under `settings` are
    # the server's own - nixvim inserts the server namespace (`nixd`, `Lua`, ...).
    servers = {
      # Lua: wezterm's extraConfig, the `__raw` blocks in this config, .luarc-free
      # analysis of the Neovim API.
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

      bashls.enable = true; # scripts/
      basedpyright.enable = true; # nixos/services/llm-logs-server (pyright itself is unfree)
      jsonls.enable = true; # flake.lock, dashboards/*.json
      yamlls.enable = true; # docker-compose.yml
      marksman.enable = true; # markdown, pairs with render-markdown
    };

    # Parameter names/types from clangd, option info from nixd.
    # (plain bool here: `plugins.lsp.inlayHints` aliases `lsp.inlayHints.enable`)
    inlayHints = true;

    # Buffer-local keymaps, registered on `LspAttach`.
    keymaps = {
      # `vim.lsp.buf.<action>`. Neovim's own defaults already cover hover (`K`),
      # `gra`/`grn`/`grr`/`gri`/`grt`/`grx` and `gO` - see `:help lsp-defaults` -
      # so only the gaps are mapped here.
      lspBuf = {
        "gd" = "definition";
        "gD" = "declaration";
        "<leader>cf" = "format";
      };

      # Anything that is not a plain `vim.lsp.buf` call
      extra = [
        {
          key = "<leader>ls";
          action = "<Cmd>LspStart<CR>";
          options.desc = "Start LSP";
        }
        {
          key = "<leader>lx";
          action = "<Cmd>LspStop<CR>";
          options.desc = "Stop LSP";
        }
        {
          key = "<leader>lR";
          action = "<Cmd>LspRestart<CR>";
          options.desc = "Restart LSP";
        }
      ];
    };
  };
}
