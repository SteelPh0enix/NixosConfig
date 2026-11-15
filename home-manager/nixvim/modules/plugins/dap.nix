{ pkgs, ... }:
let
  # lldb-dap over codelldb: free, upstream, and version-matched to the lldb CLI. Absolute paths
  # because jobstart() cannot see the launching terminal's PATH.
  lldb-dap = "${pkgs.lldb}/bin/lldb-dap";
  gdb = "${pkgs.gdb}/bin/gdb";

  # Prompt instead of guessing a build output; nvim-dap reuses the last configuration.
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
      # GDB's DAP understands program, cwd, args, env and stopOnEntry; VS Code keys are ignored.
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
  # rustaceanvim probes `lldb-dap` on PATH and looks up `dap.adapters.lldb`, so keep both names.
  extraPackages = [ pkgs.lldb ];

  plugins.dap = {
    enable = true;

    # rustaceanvim reuses dap.adapters.lldb; the adapter name is load-bearing.
    adapters.executables = {
      lldb.command = lldb-dap;

      # GDB >= 14 speaks DAP over stdio; fallback for attach-by-pid and gdb-specific commands.
      gdb = {
        command = gdb;
        args = [ "--interpreter=dap" ];
      };
    };

    configurations = {
      c = nativeConfigs;
      cpp = nativeConfigs;
      # Rust stays unset so `:RustLsp debuggables` builds the config from the cargo model.
    };
  };

  # nvim-dap-ui 4.x ships no user commands, so its keymaps call the Lua API.
  plugins.dap-ui.enable = true;

  plugins.dap-virtual-text.enable = true;

  # Registers the python adapter; the debuggee interpreter is resolved per session.
  plugins.dap-python.enable = true;

  # Open the UI with the session and close it when the debuggee exits.
  extraConfigLuaPost = ''
    do
      local dap, dapui = require('dap'), require('dapui')
      dap.listeners.before.launch.dapui_config = function() dapui.open() end
      dap.listeners.before.attach.dapui_config = function() dapui.open() end
      dap.listeners.before.event_terminated.dapui_config = function() dapui.close() end
      dap.listeners.before.event_exited.dapui_config = function() dapui.close() end
    end
  '';

  # `<leader>d` is the debug prefix; diagnostics live on `<leader>dd` in keymaps.nix.
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
