{ pkgs, ... }:
{
  # ---- LSP ----

  # External binaries that LSP servers shell out to *at runtime* - they are looked up on
  # the nvim process PATH, so they have to be in the wrapper even though nixvim already
  # puts the servers themselves there (clang-tools, nixd, bash-language-server, ...).
  #   nixfmt     - nixd `textDocument/formatting` (`settings.formatting.command`)
  #   shellcheck - bash-language-server diagnostics; without it `scripts/*.sh` get none
  #   shfmt      - bash-language-server formatting
  # (conform-nvim/nvim-lint also pull shfmt/shfmt+shellcheck via autoInstall, same
  #  derivations, so this is belt-and-braces for the LSP path alone.)
  extraPackages = [
    pkgs.nixfmt
    pkgs.shellcheck
    pkgs.shfmt
  ];

  # Signature float while typing arguments. Also covers the case where the
  # insert-mode `<C-s>` save mapping shadows Neovim's default `<C-S>` signature help.
  plugins.lsp-signature.enable = true;

  plugins.lsp = {
    enable = true;

    # ---- C / C++ ----
    # clangd reads almost all of its knobs from argv (or from a `.clangd` YAML in the repo).
    # Its LSP settings object carries very little by comparison - lspconfig types it as
    # `{ clangd = { fallbackFlags, inactiveRegions, ... } }` - and nixvim does not namespace
    # clangd at all, so `cmd` below is the right place. The binary comes from `pkgs.clang-tools`
    # via the server's `package` (-> wrapper PATH), same as before.
    servers.clangd = {
      enable = true;

      cmd = [
        "clangd"
        # Index the project in the background -> cross-file completion/goto in trees
        # bigger than the one clangd parses on demand (llama.cpp et al).
        "--background-index"
        # tidy diagnostics *through* clangd. Deliberate: adding `c`/`cpp` -> clangtidy to
        # plugins.lint would publish the same checks twice (see lint.nix).
        "--clang-tidy"
        "--completion-style=detailed"
        # No `<algorithm>` appearing in a header you never included.
        "--header-insertion=never"
        # Without .clang-format, clangd's own formatting falls back to *nothing* instead of
        # LLVM style, so `<leader>cF` (LSP-only) leaves foreign projects alone.
        # Note the asymmetry: `<leader>cf` prefers conform's `clang-format` CLI (lsp_format =
        # "fallback"), and that binary has no such switch - it still applies LLVM style when no
        # .clang-format is found. Remove `c`/`cpp` from conform's formatters_by_ft if you want
        # "no file without an explicit style gets touched".
        "--fallback-style=none"
        # `-j` stays unset: clangd defaults to all cores, and a literal here would just
        # be a machine-specific cap.
        # Cross-compiling / a compiler that is not on PATH additionally needs
        #   "--query-driver=/path/to/g++"
      ];

      # Root = where the compilation database (and the style/tidy config clangd should read)
      # lives. Spelled out rather than inherited from lspconfig because `rootMarkers` REPLACES
      # the list (`vim.lsp.config` deep-merges tables, but a list key is overwritten, not
      # appended) - the plan's 3-item version would have silently dropped `.clang-format`,
      # `.clang-tidy`, `.clangd` and `configure.ac`, all of which lspconfig 2.11 ships.
      rootMarkers = [
        "compile_commands.json"
        "compile_flags.txt"
        ".clangd"
        ".clang-tidy"
        ".clang-format"
        "configure.ac"
        ".git" # last: single .c files inside a repo still get a stable root
      ];
      # Getting a compile_commands.json there: `bear -- make` (bear is in nixos/packages/dev.nix)
      # or `-DCMAKE_EXPORT_COMPILE_COMMANDS=ON`, then symlink `build/compile_commands.json` into
      # the source root - clangd only searches the root itself. (`plugins.cmake-tools`, tier C,
      # automates that symlink via `cmake_soft_link_compile_commands`.)
    };

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
      # (bashls shells out to shellcheck/shfmt - those come from `extraPackages` above.
      #  If autodetection ever picks the wrong shell: settings.exec.shell = "/run/current-system/sw/bin/bash";)

      # ---- Python: two clients on purpose ----
      # basedpyright = types (and it never formats - `<leader>cf` still needs conform or ruff).
      # ruff         = lint + format + autofix, i.e. the rule engine that `ruff check`/`ruff format`
      #              run on CI, now with on-type diagnostics instead of on-write.
      basedpyright.enable = true; # nixos/services/llm-logs-server (pyright itself is unfree)

      # `ruff` = the built-in `ruff server` (>= 0.5.3). NOT `ruff_lsp`, which is deprecated
      # upstream and a separate python process speaking `ruff-lsp`'s private protocol.
      # Consequence: `plugins.lint.lintersByFt.python = [ "ruff" ]` is removed in lint.nix,
      # for the same reason shellcheck/clangtidy are not there.
      ruff.enable = true;

      # NOTE on basedpyright settings: nixvim does *not* namespace this server (unlike `nixd`,
      # `Lua`, `pylsp`, `rust-analyzer`, `yaml`), so anything under `settings` has to be written
      # as `settings.basedpyright.analysis.*` by hand. Left empty deliberately:
      #   * `typeCheckingMode` - basedpyright's own default is "recommended", not "standard"
      #     (that is pyright's), so pinning "standard" here would silently *relax* checks.
      #   * `useLibraryCodeForTypes` - lspconfig's own comment says explicit values override
      #     per-project config, and LSP settings beat `pyproject.toml`/[tool.basedpyright]
      #     outright: whatever is set here applies to every project.
      # Per-project strictness belongs in pyproject.toml / pyrightconfig.json.

      jsonls.enable = true; # flake.lock, dashboards/*.json
      yamlls.enable = true; # docker-compose.yml
      marksman.enable = true; # markdown, pairs with render-markdown

      # ---- CMake / TOML ----
      # CMakeLists.txt + *.cmake: completion for command/variable/target names, hover for
      # `${var}` expansion. `cmake` (the older server) is a different, weaker implementation.
      neocmake.enable = true;
      # Every .toml: Cargo.toml, pyproject.toml, ruff.toml, wezterm.lua's neighbours.
      # It also implements textDocument/formatting; conform's `taplo` CLI still wins there
      # (`lsp_format = "fallback"`), this is for the schema-aware completion + diagnostics.
      taplo.enable = true;

      # ---- Fish: deliberately no server ----
      # `pkgs.fish-lsp` exists and nixvim knows it (`servers.fish_lsp`), but fish_indent
      # (conform) + `fish -n` (lint.nix) + the fish treesitter parser already cover format,
      # syntax errors and highlighting. fish-lsp is young and moves fast; re-visit if you
      # start missing rename/goto on config.fish functions.
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
        # `<leader>cf` moved to plugins/conform-nvim.nix: it is a global
        # `require('conform').format()` now (CLI formatter with LSP fallback) instead of
        # `vim.lsp.buf.format`, which was a no-op in every filetype without a formatting
        # client (python/bash/fish/json). LSP-only formatting is still on `<leader>cF`.
      };

      # Anything that is not a plain `vim.lsp.buf` call.
      #
      # nvim-lspconfig's `:LspStart`/`:LspStop`/`:LspRestart`/`:LspInfo` do not exist on
      # Nvim >= 0.11 (plugin/lspconfig.lua returns early as soon as core's `:lsp` is
      # defined), hence Neovim's own `:lsp` subcommands (:help :lsp-enable):
      #   :lsp stop      stop clients attached to the current buffer
      #   :lsp restart   restart those clients (errors if none are attached)
      #   :lsp enable|disable [name]  toggle a config for current + future buffers
      #
      # `:lsp enable` is deliberately NOT mapped: without an explicit server name it
      # enables any config registered for the filetype, including Neovim's built-in
      # ones - bare `:lsp enable` attached `nil_ls` in a Nix buffer. To re-attach after
      # `:lsp stop`, firing FileType again is enough (verified), which is what <leader>ls does.
      extra = [
        {
          # clangd's private `textDocument/switchSourceHeader` request. No native equivalent
          # (`vim.lsp.buf` has nothing for it), but nvim-lspconfig's own `lsp/clangd.lua`
          # registers a buffer-local `:LspClangdSwitchSourceHeader` in its on_attach - verified:
          #   nvim --headless -c 'echo globpath(&rtp,"lsp/clangd.lua")'  -> lspconfig/lsp/clangd.lua
          # so no extra plugin is needed. (plugins.clangd-extensions would only add `:ClangdAST`,
          # `:ClangdOpenOutputFile`, `:ClangdMemoryUsage` - enable it if you want those.)
          # Like the command it calls, this map is buffer-local on LspAttach and E492s in
          # buffers where clangd is not the client.
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
