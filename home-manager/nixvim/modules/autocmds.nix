{ ... }:
{
  # NixVim's autocmd options are `autoCmd`/`autoGroups`; each entry maps to
  # `nvim_create_autocmd` with either `callback` (raw Lua) or `command` (viml).
  autoCmd = [
    # Flash the yanked region (vim.hl is the 0.10+ home for on_yank).
    {
      event = [ "TextYankPost" ];
      desc = "Highlight yanked text";
      callback.__raw = ''
        function()
          vim.hl.on_yank({ timeout = 200 })
        end
      '';
    }

    # Reopen where you left off; `"` is the last cursor position, guarded against a stale
    # mark past the end of a file that shrank since.
    {
      event = [ "BufReadPost" ];
      desc = "Restore last cursor position";
      callback.__raw = ''
        function()
          local mark = vim.api.nvim_buf_get_mark(0, '"')
          local lcount = vim.api.nvim_buf_line_count(0)
          if mark[1] > 0 and mark[1] <= lcount then
            pcall(vim.api.nvim_win_set_cursor, 0, mark)
          end
        end
      '';
    }

    # opts.autoread reloads silently when the buffer is unmodified - this makes that visible.
    {
      event = [ "FileChangedShellPost" ];
      desc = "Autoreload changed files";
      callback.__raw = ''
        function()
          vim.notify('File changed on disk: reloaded', vim.log.levels.WARN)
        end
      '';
    }

    # Terminal buffers (toggleterm, `:terminal`, dap's term executor) are not code.
    {
      event = [ "TermOpen" ];
      desc = "Clean up terminal windows";
      command = "setlocal nonumber norelativenumber signcolumn=no foldcolumn=0";
    }

    # Per-filetype width guides, kept in sync with the real formatter configs
    # (rustfmt 100, ruff 88, clang-format 80/120, nixfmt 100) instead of a global colorcolumn.
    {
      event = [ "FileType" ];
      pattern = [ "rust" ];
      command = "setlocal colorcolumn=100";
    }
    {
      event = [ "FileType" ];
      pattern = [ "python" ];
      command = "setlocal colorcolumn=88,120 textwidth=88";
    }
    {
      event = [ "FileType" ];
      pattern = [
        "c"
        "cpp"
      ];
      command = "setlocal colorcolumn=80,120";
    }
    {
      event = [ "FileType" ];
      pattern = [ "nix" ];
      command = "setlocal colorcolumn=100";
    }
  ];
}
