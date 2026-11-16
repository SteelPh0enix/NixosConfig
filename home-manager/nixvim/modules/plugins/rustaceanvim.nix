_: {
  plugins.rustaceanvim = {
    enable = true;

    settings = {
      server.default_settings."rust-analyzer" = {
        # Clippy rather than cargo check, deterministically: tools.enable_clippy only flips this
        # when it *detects* clippy, and flyCheck needs the same.
        check = {
          command = "clippy";
          allTargets = true;
        };

        procMacro.enable = true;
        cargo.buildScripts.enable = true;

        inlayHints.bindingModeHints.enable = true;

        # `rustfmt.extraArgs` deliberately unset: rust-analyzer passes each crate's `--edition`
        # itself, so a hardcoded one would apply to all of them.
      };

      # "quickfix" cannot run interactive binaries, which is what runnables are.
      tools.executor = "termopen";

      # `dap.adapter` stays default: dap.nix registers the `lldb` adapter it probes for.
    };
  };

  # `:RustLsp` is buffer-local, so these are per Rust buffer; FileType rather than LspAttach, so
  # they exist while the server is still indexing.
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
