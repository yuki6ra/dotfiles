local add, now, later = MiniDeps.add, MiniDeps.now, MiniDeps.later

-- ファイル変更を可視化
-- `ghgh`: 現在行をステージング
-- `ghip`: 現在段落をステージング
later(function()
  require('mini.diff').setup()
end)

-- `:Git`でgit操作
later(function()
  require('mini.git').setup()

  vim.keymap.set({ 'n', 'x' }, '<space>gs', MiniGit.show_at_cursor, { desc = 'Show at cursor' })
end)