{ pkgs, ... }:
{
  # `pkgs.rustToolchain` (nix/overlays/rust-toolchain.nix) is also what nixos/packages/dev.nix
  # installs, so the server, `cargo` and the proc-macro server are one release.
  #
  # Repointing nixvim's own `dependencies.rust-analyzer` (rather than `plugins.<name>.package`,
  # which would swap the *vim plugin*) keeps `<toolchain>/bin` on the wrapper PATH ahead of
  # nixpkgs' standalone rust-analyzer. Dependencies land *after* conform's tools, so `rustfmt`
  # still resolves to conform's copy - the same binary `<leader>cf` calls.
  dependencies.rust-analyzer.package = pkgs.rustToolchain;

  # ---- Rust ----
  plugins.rustaceanvim = {
    enable = true;

    settings = {
      # The `"rust-analyzer"` key is rustaceanvim's namespacing convention; it merges the
      # namespace away before sending the settings.
      server.default_settings."rust-analyzer" = {
        # Diagnostics from clippy rather than cargo check, deterministically (tools.enable_clippy
        # only flips this when it *detects* clippy) and for flyCheck too.
        check = {
          command = "clippy";
          allTargets = true; # tests, benches, examples - not just the lib
        };

        procMacro.enable = true; # the reason for the toolchain pin above
        cargo.buildScripts.enable = true; # build.rs-generated code (tonic, bindgen, ...)

        # `ref mut binding @ subpattern` hints - the class rust-analyzer leaves off by default.
        inlayHints.bindingModeHints.enable = true;

        # `rustfmt.extraArgs` deliberately unset: rust-analyzer passes `--edition <crate edition>`
        # itself, so a hardcoded edition would apply one crate's edition to all of them.
      };

      # Native terminal split: "quickfix" (the other legal value) cannot run interactive
      # binaries, which is most of what `:RustLsp runnables` is for.
      tools.executor = "termopen";

      # `dap.adapter` stays at its default, which dap.nix satisfies: rustaceanvim probes
      # `lldb-dap` by name and reuses the existing `dap.adapters.lldb`.
    };
  };

  # ---- Rust-only keymaps ----
  # `:RustLsp` is buffer-local, so these are registered per Rust buffer (a global map would
  # E492 elsewhere). FileType rather than LspAttach: the keys then exist while the server is
  # still indexing. Neovim's own `gra`/`grn`/`grr`/`gri`/`grt` cover the rest.
  autoCmd = [
    {
      event = [ "FileType" ];
      pattern = [ "rust" ];
      desc = "Rust-specific keymaps (rustaceanvim)";
      callback.__raw = ''
        function()
          local map = function(lhs, rhs, desc)
            vim.keymap.set('n', lhs, rhs, { buffer = true, desc = desc })
          end
          map('<leader>rt', '<Cmd>RustLsp testables<CR>', 'Run testables')
          map('<leader>rr', '<Cmd>RustLsp runnables<CR>', 'Run runnables')
          map('<leader>rd', '<Cmd>RustLsp debuggables<CR>', 'Debug debuggables (nvim-dap + lldb-dap)')
          map('<leader>rp', '<Cmd>RustLsp parentModule<CR>', 'Open parent module')
          map('<leader>re', '<Cmd>RustLsp expandMacro<CR>', 'Expand macro (recursive)')
          map('<leader>rc', '<Cmd>RustLsp codeAction<CR>', 'Grouped code actions')
          map('<leader>rf', '<Cmd>RustLsp flyCheck run<CR>', 'cargo check (fly-check)')
          map('<leader>ro', '<Cmd>RustLsp openCargo<CR>', 'Open Cargo.toml of this package')
          map('<leader>rx', '<Cmd>RustLsp relatedDiagnostics<CR>', 'Related diagnostics -> quickfix')
        end
      '';
    }
  ];
}
