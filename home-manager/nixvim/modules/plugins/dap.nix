{ pkgs, ... }:
let
  # Both debug adapters come from packages this machine already installs via
  # `nixos/packages/dev.nix` (`lldb` -> bin/lldb-dap, `gdb`), so the wrapper points at
  # store paths that exist on disk anyway. Absolute paths rather than bare names:
  # nvim-dap spawns them through jobstart(), and a store path cannot be shadowed by
  # whatever $PATH the terminal that launched nvim happened to have.
  #
  # Why lldb-dap and not codelldb (which is what the review doc suggested):
  #   * `pkgs.lldb`'s lldb-dap is free, upstream (LLVM's own adapter), version-matched
  #     to the `lldb` CLI used for the manual escape hatch, and already on this system.
  #     Verified here: `printf 'Content-Length: ...\r\n\r\n{"command":"initialize",...}'
  #     | lldb-dap` -> initialize response with the cpp_catch/cpp_throw filters.
  #   * codelldb is only reachable through `pkgs.vscode-extensions.vadimcn.vscode-lldb`
  #     (MIT, so not an unfree issue - but it is an unpacked-vsix plus a prebuilt adapter
  #     pinned to LLVM 19 (its closure pulls libcxx-19.1.7), i.e. a *second*, older LLDB
  #     next to the lldb 21.1.8 the rest of the system uses).
  #   * `plugins.dap-lldb` is codelldb-only: its setup() hardcodes
  #     `{ type = "server", port = "${port}", executable.args = { "--port", "${port}" } }`
  #     (lua/dap-lldb.lua:212), and lldb-dap speaks stdio / `--connection listen://host:port`,
  #     not `--port`. Feeding it the codelldb path would just fail to connect.
  #     -> the ready-made c/cpp/rust configurations are hand-written below instead.
  #
  # Switching to codelldb later is a 3-line change (and then dap-lldb becomes usable):
  #   plugins.dap.adapters.servers.codelldb = {
  #     port = "\${port}";                                    # nvim-dap substitutes a free port
  #     executable.command = "${pkgs.vscode-extensions.vadimcn.vscode-lldb}/share/vscode/extensions/vadimcn.vscode-lldb/adapter/codelldb";
  #   };
  lldb-dap = "${pkgs.lldb}/bin/lldb-dap";
  gdb = "${pkgs.gdb}/bin/gdb";

  # `program` prompts instead of guessing: C/C++ projects here have no single
  # build output (cmake build dirs vary per project, `nix build` results differ),
  # and nvim-dap reuses the last configuration - `:help dap.run_last()` / <leader>dl.
  programPrompt = {
    __raw = ''
      function()
        return vim.fn.input('Path to executable: ', vim.fn.getcwd() .. '/', 'file')
      end
    '';
  };

  # Returns a *number*: gdb's python handler annotates `pid: Optional[int]`
  # (share/gdb/python/gdb/dap/launch.py) and rejects a string.
  pickProcess = {
    __raw = "require('dap.utils').pick_process";
  };

  # Same four entries for c and cpp; nvim-dap keys configurations by filetype, so
  # `:DapContinue` (<leader>dc) in a C++ buffer opens a fuzzy picker over these.
  nativeConfigs = [
    {
      name = "lldb-dap: launch";
      type = "lldb";
      request = "launch";
      program = programPrompt;
      # nvim-dap expands ${workspaceFolder} -> getcwd() before sending
      # (lua/dap.lua `expand_config_variables`); the adapters themselves never see it.
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
      # GDB's built-in DAP understands exactly: program, cwd, args, env,
      # stopOnEntry, stopAtBeginningOfMainSubprogram (+ init/preRun commands).
      # Anything VS-Code-shaped (sourceMap, MIMode, ...) is silently ignored.
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
  # rustaceanvim resolves its *default* DAP adapter at runtime with
  # `vim.fn.executable('codelldb')` / `('lldb-dap')` (lua/rustaceanvim/config/internal.lua).
  # If neither is found it returns `false` and `:RustLsp debuggables` refuses to run
  # even though `dap.adapters.lldb` exists - so the probe has to succeed, which means
  # lldb-dap must be resolvable *by name* on the nvim process PATH. makeBinPath puts
  # `<lldb>/bin` there; the probe then resolves it to the very same binary as
  # `lldb-dap` above.
  extraPackages = [ pkgs.lldb ];

  # ---- nvim-dap ----
  plugins.dap = {
    enable = true;

    adapters.executables = {
      # The adapter *name* is load-bearing: rustaceanvim looks up `dap.adapters.lldb`
      # (executable adapter) or `dap.adapters.codelldb` (server adapter) and only
      # registers its own when that key is still nil
      # (lua/rustaceanvim/dap.lua: `if dap.adapters[adapter_key] == nil`). Naming this
      # one `lldb` therefore makes `:RustLsp debuggables` reuse it instead of
      # duplicating an adapter pointing at the same binary.
      lldb = {
        command = lldb-dap;
      };

      # GDB >= 14 exposes DAP over stdio; `--interpreter=dap` is the spelling since 15
      # (verified against the installed gdb 17.2: it answers `initialize` with
      # `success: true`). Kept as the fallback for attach-by-pid of processes lldb-dap
      # cannot grab, and for the gdb-specific commands (`set scheduler-locking`,
      # `catch fork`, core files via the console).
      gdb = {
        command = gdb;
        args = [ "--interpreter=dap" ];
      };
    };

    configurations = {
      c = nativeConfigs;
      cpp = nativeConfigs;

      # rust deliberately NOT set: `:RustLsp debuggables` builds the launch config
      # from the cargo model (correct binary, correct env from `.cargo/config.toml`,
      # dynamic library paths) - a static entry here would only add a worse option to
      # the same picker. rustaceanvim reads `dap.configurations.rust` solely as a
      # fallback template when its own default is disabled.
    };

    # signs left at nixvim's defaults, which are byte-identical to nvim-dap's own
    # (B/C/R/L/→ with texthl=SignColumn). `plugins.dap.signs.dapBreakpoint.text = "●";`
    # if the letter is too quiet next to gitsigns in a `signcolumn=yes` gutter.
  };

  # ---- UI ----
  # NOTE: nvim-dap-ui 4.x ships no user commands at all (there is no plugin/ dir in
  # the package, and `DapUIToggle` is gone) -> the keymaps below call the Lua API.
  plugins.dap-ui.enable = true;

  # Inline variable values next to the source while stopped.
  plugins.dap-virtual-text.enable = true;

  # ---- Python ----
  # setup() registers `dap.adapters.python` (+ the alias `dap.adapters.debugpy`) and
  # inserts `file`, `file:args`, `module`, `test` launch configs into
  # `dap.configurations.python`. It registers no commands and no keymaps of its own -
  # `<leader>dc` in a .py buffer is what picks them up.
  plugins.dap-python = {
    enable = true;
    # `adapterPythonPath` (nixvim default) = pkgs.python3 3.14 + debugpy 1.8.21.
    # That interpreter only *hosts* the adapter (`<it> -m debugpy.adapter`); the
    # debuggee interpreter is resolved per session by dap-python's enrich_config:
    #   config.python  ->  $VIRTUAL_ENV / $CONDA_PREFIX  ->  nearest ./venv,.venv,env,.env
    # `uv venv` projects land in the last two branches, so neither the venv nor the
    # nvim wrapper needs debugpy inside it.
    # Pin one per project at runtime instead: :lua require('dap-python').setup('/abs/.venv/bin/python')
    # (and if a project ever *is* a uv-managed venv without a resolvable interpreter,
    #  adapterPythonPath can be set to `${pkgs.uv}/bin/uv` - the plugin detects the
    #  basename and runs `uv run --with debugpy python -m debugpy.adapter`.)
  };

  # Open the dap-ui windows on session start, close them when the debuggee exits
  # (upstream README recommendation). `dapui.open/close` accept "sidebar"/"tray" if
  # you'd rather only get one of the two automatically.
  #
  # All three adapters were smoke-tested end to end through the built wrapper
  # (headless nvim + dap.run() against a trivial program):
  #   lldb   -> initialize / stopped(entry) / terminate / exited
  #   gdb    -> initialize / stopped(entry) / terminate / exited
  #   python -> initialize / stopped(entry) / terminate
  # `Error retrieving stack traces: cancelled` in those runs is expected (terminate()
  # races the stackTrace request). The python probe had to use `console =
  # "internalConsole"` - integratedTerminal asks Neovim for a terminal window, which a
  # headless nvim cannot give. The real editor keeps dap-python's own default.
  extraConfigLuaPost = ''
    do
      local dap, dapui = require('dap'), require('dapui')
      dap.listeners.before.launch.dapui_config = function() dapui.open() end
      dap.listeners.before.attach.dapui_config = function() dapui.open() end
      dap.listeners.before.event_terminated.dapui_config = function() dapui.close() end
      dap.listeners.before.event_exited.dapui_config = function() dapui.close() end
    end
  '';

  # ---- Keymaps ----
  # `<leader>d` is the debug prefix now. The line-diagnostics float that used to sit
  # on it moved to `<leader>dd` in keymaps.nix: a bare `<leader>d` *and* `<leader>dX`
  # both being mapped means the bare one waits out `timeoutlen` on every press.
  # (`<C-W>d` is Neovim's own equivalent, `:lua vim.diagnostic.open_float()` if the
  # mapping is dropped entirely.)
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
      # With no argument: run the first configuration of this filetype, or pick one
      # when several exist (c/cpp -> the four above).
      key = "<leader>dc";
      action = "<Cmd>DapContinue<CR>";
      options.desc = "Continue / start debugging";
    }
    {
      # Temporary breakpoint at the cursor, continue, remove it again.
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
      # `:DapRunLast` does not exist in nvim-dap 0.10 (only the Lua API), unlike the
      # commands above - hence the __raw.
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
      # The "hover" of nvim-dap-ui: evaluates the word under the cursor (or the
      # visual selection) in a float. 4.x renamed the old `hover()` function to
      # `eval()` + a `hover` *element*, and there is no `:DapUIHover` command.
      # `K` stays LSP hover - this is the runtime value, not the declaration.
      key = "<leader>de";
      action.__raw = "function() require('dapui').eval() end";
      options.desc = "Evaluate under cursor (dap-ui hover)";
    }
    {
      # No element id -> dap-ui asks which one (scopes/stacks/watches/console/repl/hover).
      key = "<leader>df";
      action.__raw = "function() require('dapui').float_element() end";
      options.desc = "Floating dap-ui element";
    }
  ];
}
