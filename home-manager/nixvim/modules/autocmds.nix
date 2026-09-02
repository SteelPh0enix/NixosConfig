{ ... }:
{
  # ---- Autocmds ----
  # NixVim's autocmd options are `autoCmd` / `autoGroups` (capital C). Each entry maps to
  # `nvim_create_autocmd`: `event`, `pattern`, `desc`, and exactly one of `callback`
  # (raw Lua function) / `command` (viml string).
  autoCmd = [
    # Flash the yank region. `vim.hl` is the 0.10+ home for `on_yank` (vim.hl.on_yank
    # exists in 0.12.5; the old `vim.highlight.on_yank` is a deprecated alias).
    {
      event = [ "TextYankPost" ];
      desc = "Highlight yanked text";
      callback.__raw = ''
        function()
          vim.hl.on_yank({ timeout = 200 })
        end
      '';
    }

    # Reopen where you left off. The `"` mark is the last cursor position; guard against a
    # stale mark pointing past the end of a file that shrank since the last session.
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

    # Companion to `opts.autoread = true`: autoread silently reloads a buffer that has no
    # unsaved changes, and prompts when it does. This is the notification for the silent
    # case (nixfmt on another tty, `git checkout`, codegen, ...).
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

    # ---- Per-filetype line-width guides ----
    # Replaces the old global `colorcolumn = "80,100,120"`. Keep these in sync with the
    # real formatter configs of each project (`.clang-format` ColumnLimit,
    # `rustfmt.toml` max_width, `ruff.toml` line-length) - a guide nobody matches is noise.
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
