local now = Config.now

-- snacks.nvimのinstall
-- ref: https://wagomu.me/blog/2025-02-26-vim-ekiden
now(function()
  vim.pack.add({ 'https://github.com/folke/snacks.nvim' })
  require('snacks').setup({
    -- animate = { enabled = false },
    -- bigfile = { enabled = true },
    -- indent = { enabled = true },
    -- input = { enabled = true },
    -- picker = { enabled = true },
    -- scope = { enabled = true },
    -- statuscolumn = { enabled = true },
    -- terminal = { enabled = true },
    image = {
      resolve = function(path, src)
        local api = require "obsidian.api"
        if api.path_is_note(path) then
          return api.resolve_attachment_path(src)
        end
      end,
    },
  })

  -- ファイルピッカーを開く
  -- vim.keymap.set('n', '<Leader>e', Snacks.picker.files, { desc = 'open file' })
  -- バッファーを全部削除する
  -- vim.keymap.set('n', '<Leader>bd', Snacks.bufdelete.delete, { desc = 'delete buffer' })
  -- ターミナルをトグルする
  -- vim.keymap.set('n', '<Leader><Leader>', Snacks.terminal.toggle, { desc = 'toggle terminal' })
  -- vim.keymap.set('t', '<Leader><Leader>', Snacks.terminal.toggle, { desc = 'toggle terminal' })
end)

-- vim.cmd.colorscheme('minicyan')
