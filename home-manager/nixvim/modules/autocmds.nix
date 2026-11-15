_: {
  autoCmd = [
    # vim.hl is the 0.10+ home for on_yank.
    {
      event = [ "TextYankPost" ];
      desc = "Highlight yanked text";
      callback.__raw = ''
        function()
          vim.hl.on_yank({ timeout = 200 })
        end
      '';
    }

    # Guard the last-position mark against a file that shrank.
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

    # opts.autoread reloads silently; this makes it visible.
    {
      event = [ "FileChangedShellPost" ];
      desc = "Autoreload changed files";
      callback.__raw = ''
        function()
          vim.notify('File changed on disk: reloaded', vim.log.levels.WARN)
        end
      '';
    }

    {
      event = [ "TermOpen" ];
      desc = "Clean up terminal windows";
      command = "setlocal nonumber norelativenumber signcolumn=no foldcolumn=0";
    }

    # Guides mirror the formatter configs (rustfmt 100, ruff 88, clang-format 80/120,
    # nixfmt 100) instead of a global colorcolumn.
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
