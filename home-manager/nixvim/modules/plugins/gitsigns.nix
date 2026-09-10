{ ... }:
{
  # gitsigns 2.x ships no default keymaps and the nixvim module has no keymap option, so
  # `settings.on_attach` is the only hook. The `bufnr` parameter is used explicitly because
  # gitsigns can attach a buffer that is not the current one.
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
