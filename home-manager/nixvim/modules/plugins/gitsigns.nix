_: {
  # gitsigns 2.x has no default keymaps and nixvim has no keymap option, so on_attach is the
  # hook. bufnr is the attached buffer, which may not be the current one.
  plugins.gitsigns = {
    enable = true;

    settings.on_attach.__raw = ''
      function(bufnr)
        local map = function(lhs, rhs, desc)
          vim.keymap.set('n', lhs, rhs, { buffer = bufnr, desc = desc, silent = true })
        end

        map(']c', '<Cmd>Gitsigns nav_hunk next<CR>', 'Next hunk')
        map('[c', '<Cmd>Gitsigns nav_hunk prev<CR>', 'Prev hunk')
        map('<leader>hs', '<Cmd>Gitsigns stage_hunk<CR>', 'Stage hunk')
        map('<leader>hr', '<Cmd>Gitsigns reset_hunk<CR>', 'Reset hunk')
        map('<leader>hp', '<Cmd>Gitsigns preview_hunk<CR>', 'Preview hunk')
        map('<leader>hb', '<Cmd>Gitsigns blame_line<CR>', 'Blame line')
        map('<leader>hq', '<Cmd>Gitsigns qflist<CR>', 'All hunks (quickfix)')
        map('<leader>ht', '<Cmd>Gitsigns toggle_deleted<CR>', 'Toggle deleted')
      end
    '';
  };
}
