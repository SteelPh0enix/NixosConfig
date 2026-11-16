{ pkgs, ... }:
let
  # Absolute paths: nvim-dap spawns adapters through jobstart(), so $PATH cannot shadow them.
  # lldb-dap over codelldb: free, upstream, version-matched - and stdio-only, while
  # plugins.dap-lldb expects codelldb's `--port` server mode.
  lldb-dap = "${pkgs.lldb}/bin/lldb-dap";
  gdb = "${pkgs.gdb}/bin/gdb";

  # No single build output to guess at; nvim-dap reuses the last configuration (<leader>dl).
  programPrompt = {
    __raw = ''
      function()
        return vim.fn.input('Path to executable: ', vim.fn.getcwd() .. '/', 'file')
      end
    '';
  };

  # Must be a *number*: gdb's python DAP handler annotates `pid: Optional[int]`.
  pickProcess = {
    __raw = "require('dap.utils').pick_process";
  };

  nativeConfigs = [
    {
      name = "lldb-dap: launch";
      type = "lldb";
      request = "launch";
      program = programPrompt;
      # nvim-dap expands ${workspaceFolder} before sending; the adapters never see it.
      cwd = "\${workspaceFolder}";
      stopOnEntry = false;
    }
    {
      name = "lldb-dap: attach";
      type = "lldb";
      request = "attach";
      pid = pickProcess;
    }
    {
      # GDB's own DAP understands program, cwd, args, env, stopOnEntry and
      # stopAtBeginningOfMainSubprogram; VS-Code-shaped keys are silently ignored.
      name = "gdb: launch";
      type = "gdb";
      request = "launch";
      program = programPrompt;
      cwd = "\${workspaceFolder}";
      stopOnEntry = false;
    }
    {
      name = "gdb: attach";
      type = "gdb";
      request = "attach";
      pid = pickProcess;
    }
  ];
in
{
  # rustaceanvim probes for `codelldb`/`lldb-dap` on nvim's PATH before allowing debuggables.
  extraPackages = [ pkgs.lldb ];

  plugins.dap = {
    enable = true;

    # The adapter *name* is load-bearing: rustaceanvim looks up `dap.adapters.lldb` and only
    # registers its own when that key is nil, so `:RustLsp debuggables` reuses this one.
    adapters.executables = {
      lldb.command = lldb-dap;

      # GDB >= 14 speaks DAP over stdio: fallback for gdb-only commands and remote attaches.
      gdb = {
        command = gdb;
        args = [ "--interpreter=dap" ];
      };
    };

    configurations = {
      c = nativeConfigs;
      cpp = nativeConfigs;
      # rust left unset: `:RustLsp debuggables` builds a better config from the cargo model.
    };

  };

  plugins.dap-ui.enable = true;

  plugins.dap-virtual-text.enable = true;

  # The interpreter is resolved per session ($VIRTUAL_ENV / $CONDA_PREFIX / nearest .venv).
  plugins.dap-python.enable = true;

  extraConfigLuaPost = ''
    do
      local dap, dapui = require('dap'), require('dapui')
      dap.listeners.before.launch.dapui_config = function() dapui.open() end
      dap.listeners.before.attach.dapui_config = function() dapui.open() end
      dap.listeners.before.event_terminated.dapui_config = function() dapui.close() end
      dap.listeners.before.event_exited.dapui_config = function() dapui.close() end
    end
  '';

  keymaps = [
    {
      key = "<leader>db";
      action = "<Cmd>DapToggleBreakpoint<CR>";
      options.desc = "Toggle breakpoint";
    }
    {
      key = "<leader>dC";
      action = "<Cmd>DapClearBreakpoints<CR>";
      options.desc = "Clear all breakpoints";
    }
    {
      key = "<leader>dc";
      action = "<Cmd>DapContinue<CR>";
      options.desc = "Continue / start debugging";
    }
    {
      key = "<leader>da";
      action.__raw = "function() require('dap').run_to_cursor() end";
      options.desc = "Run to cursor";
    }
    {
      key = "<leader>ds";
      action = "<Cmd>DapStepOver<CR>";
      options.desc = "Step over";
    }
    {
      key = "<leader>di";
      action = "<Cmd>DapStepInto<CR>";
      options.desc = "Step into";
    }
    {
      key = "<leader>do";
      action = "<Cmd>DapStepOut<CR>";
      options.desc = "Step out";
    }
    {
      key = "<leader>dt";
      action = "<Cmd>DapTerminate<CR>";
      options.desc = "Terminate session";
    }
    {
      key = "<leader>dl";
      action.__raw = "function() require('dap').run_last() end";
      options.desc = "Re-run last configuration";
    }
    {
      key = "<leader>dr";
      action = "<Cmd>DapToggleRepl<CR>";
      options.desc = "Toggle DAP REPL";
    }
    {
      key = "<leader>du";
      action.__raw = "function() require('dapui').toggle() end";
      options.desc = "Toggle DAP UI (sidebar + tray)";
    }
    {
      key = "<leader>de";
      action.__raw = "function() require('dapui').eval() end";
      options.desc = "Evaluate under cursor (dap-ui hover)";
    }
    {
      key = "<leader>df";
      action.__raw = "function() require('dapui').float_element() end";
      options.desc = "Floating dap-ui element";
    }
  ];
}
