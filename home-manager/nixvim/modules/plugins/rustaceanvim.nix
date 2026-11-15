_: {
  plugins.rustaceanvim = {
    enable = true;

    settings = {
      # rustaceanvim merges its namespace away before sending the settings.
      server.default_settings."rust-analyzer" = {
        # clippy instead of cargo check, for flyCheck too.
        check = {
          command = "clippy";
          allTargets = true;
        };

        procMacro.enable = true;
        cargo.buildScripts.enable = true;

        # Binding-mode hints are off by default in rust-analyzer.
        inlayHints.bindingModeHints.enable = true;

        # `rustfmt.extraArgs` stays unset: rust-analyzer passes each crate's edition itself.
      };

      # "quickfix" cannot run interactive binaries.
      tools.executor = "termopen";

      # dap.nix provides `dap.adapters.lldb`, which rustaceanvim reuses.
    };
  };

  # `:RustLsp` is buffer-local, so map per Rust buffer. FileType rather than LspAttach: the
  # keys exist while the server is still indexing.
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
