{ pkgs, ... }:
let
  # Absolute paths: nvim-dap spawns adapters through jobstart(), and a store path cannot be
  # shadowed by whatever $PATH the launching terminal had.
  # lldb-dap over codelldb: it is free, upstream (LLVM's own adapter) and version-matched to
  # the lldb CLI. codelldb is only reachable as an unpacked VS Code extension pinned to an
  # older LLVM, and plugins.dap-lldb hardcodes codelldb's `--port` server mode, which
  # lldb-dap (stdio / `--connection listen://`) does not speak - hence hand-written configs.
  lldb-dap = "${pkgs.lldb}/bin/lldb-dap";
  gdb = "${pkgs.gdb}/bin/gdb";

  # C/C++ projects here have no single build output, so prompt instead of guessing;
  # nvim-dap reuses the last configuration (<leader>dl).
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
      # GDB's built-in DAP understands: program, cwd, args, env, stopOnEntry,
      # stopAtBeginningOfMainSubprogram (+ init/preRun commands). VS-Code-shaped keys are
      # silently ignored.
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
  # rustaceanvim probes its default adapter with `vim.fn.executable('codelldb')` /
  # `('lldb-dap')` and refuses to run `:RustLsp debuggables` when neither resolves by name,
  # so lldb-dap has to be on the nvim PATH as well.
  extraPackages = [ pkgs.lldb ];

  plugins.dap = {
    enable = true;

    # The adapter *name* is load-bearing: rustaceanvim looks up `dap.adapters.lldb` and only
    # registers its own when that key is nil, so `:RustLsp debuggables` reuses this one.
    adapters.executables = {
      lldb.command = lldb-dap;

      # GDB >= 14 speaks DAP over stdio. Fallback for attach-by-pid lldb-dap cannot grab and
      # for gdb-specific commands (scheduler-locking, core files).
      gdb = {
        command = gdb;
        args = [ "--interpreter=dap" ];
      };
    };

    configurations = {
      c = nativeConfigs;
      cpp = nativeConfigs;
      # rust left unset: `:RustLsp debuggables` builds the config from the cargo model
      # (correct binary + env), which a static entry could only compete with badly.
    };

    # signs stay at nixvim's defaults (identical to nvim-dap's own).
  };

  # nvim-dap-ui 4.x ships no user commands at all -> the keymaps call the Lua API.
  plugins.dap-ui.enable = true;

  # Inline variable values next to the source while stopped.
  plugins.dap-virtual-text.enable = true;

  # Registers dap.adapters.python (+ `debugpy` alias) and the python launch configs; no
  # commands or keymaps of its own. The debuggee interpreter is resolved per session
  # ($VIRTUAL_ENV / $CONDA_PREFIX / nearest .venv), so uv venvs need nothing installed here.
  plugins.dap-python.enable = true;

  # Open the UI on session start, close it when the debuggee exits.
  extraConfigLuaPost = ''
    do
      local dap, dapui = require('dap'), require('dapui')
      dap.listeners.before.launch.dapui_config = function() dapui.open() end
      dap.listeners.before.attach.dapui_config = function() dapui.open() end
      dap.listeners.before.event_terminated.dapui_config = function() dapui.close() end
      dap.listeners.before.event_exited.dapui_config = function() dapui.close() end
    end
  '';

  # `<leader>d` is the debug prefix; the line-diagnostics float that used to sit on it moved
  # to `<leader>dd` in keymaps.nix (a bare prefix map would wait out `timeoutlen` on each press).
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
      # No argument: run the first configuration of this filetype, or pick when several exist.
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
      # Lua API only - there is no `:DapRunLast` command.
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
      # Runtime value of the word under the cursor; `K` stays LSP hover.
      key = "<leader>de";
      action.__raw = "function() require('dapui').eval() end";
      options.desc = "Evaluate under cursor (dap-ui hover)";
    }
    {
      # No element id -> dap-ui asks which one.
      key = "<leader>df";
      action.__raw = "function() require('dapui').float_element() end";
      options.desc = "Floating dap-ui element";
    }
  ];
}
