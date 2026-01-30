local add, now, later = MiniDeps.add, MiniDeps.now, MiniDeps.later
require('utils.bool_fn')
require('utils.user_command')

now(function()
  require('mini.misc').setup()

  -- カーソル位置の保存
  MiniMisc.setup_restore_cursor()

  -- ステータスラインの表示 / 非表示
  vim.api.nvim_create_user_command('Zoom', function()
    MiniMisc.zoom(0, {})
  end, { desc = 'Zoom current buffer' })
  vim.keymap.set('n', 'mz', '<cmd>Zoom<cr>', { desc = 'Zoom current buffer' })
end)

-- 括弧・クォート編集支援系
-- ペアとなる文字を自動入力
later(function()
  require('mini.pairs').setup()
end)

-- 既存の文字に括弧を追加・先序
later(function()
  require('mini.surround').setup()
end)

-- テキストオブジェクトの拡充
later(function()
  local gen_ai_spec = require('mini.extra').gen_ai_spec
  require('mini.ai').setup({
    custom_textobjects = {
      B = gen_ai_spec.buffer(),
      D = gen_ai_spec.diagnostic(),
      I = gen_ai_spec.indent(),
      L = gen_ai_spec.line(),
      N = gen_ai_spec.number(),
      J = { { '()%d%d%d%d%-%d%d%-%d%d()', '()%d%d%d%d%/%d%d%/%d%d()' } }
    },
  })
end)

-- lsp補完 + ファイル内 / 単語補完
later(function()
  require('mini.fuzzy').setup()
  require('mini.completion').setup({
    lsp_completion = {
      process_items = MiniFuzzy.process_lsp_items,
    },
  })

  -- improve fallback completion
  vim.opt.complete = { '.', 'w', 'k', 'b', 'u' }
  vim.opt.completeopt:append('fuzzy')
  vim.opt.dictionary:append('/usr/share/dict/words')

  -- define keycodes
  local keys = {
    cn = vim.keycode('<c-n>'),
    cp = vim.keycode('<c-p>'),
    ct = vim.keycode('<c-t>'),
    cd = vim.keycode('<c-d>'),
    cr = vim.keycode('<cr>'),
    cy = vim.keycode('<c-y>'),
  }

  -- select by <tab>/<s-tab>
  vim.keymap.set('i', '<tab>', function()
    -- popup is visible -> next item
    -- popup is NOT visible -> add indent
    return vim.bool_fn.pumvisible() and keys.cn or keys.ct
  end, { expr = true, desc = 'Select next item if popup is visible' })
  vim.keymap.set('i', '<s-tab>', function()
    -- popup is visible -> previous item
    -- popup is NOT visible -> remove indent
    return vim.bool_fn.pumvisible() and keys.cp or keys.cd
  end, { expr = true, desc = 'Select previous item if popup is visible' })

  -- complete by <cr>
  vim.keymap.set('i', '<cr>', function()
    if not vim.bool_fn.pumvisible() then
      -- popup is NOT visible -> insert newline
      return require('mini.pairs').cr()
    end
    local item_selected = vim.fn.complete_info()['selected'] ~= -1
    if item_selected then
      -- popup is visible and item is selected -> complete item
      return keys.cy
    end
    -- popup is visible but item is NOT selected -> hide popup and insert newline
    return keys.cy .. keys.cr
  end, { expr = true, desc = 'Complete current item if item is selected' })

  require('mini.snippets').setup({
    mappings = {
      jump_prev = '<c-k>',
    },
  })
end)

-- オペレータを追加
-- ref: https://zenn.dev/kawarimidoll/books/6064bf6f193b51/viewer/eacaef
later(function()
  require('mini.operators').setup({
    replace = { prefix = 'R' },
    exchange = { prefix = 'g/' },
  })

  vim.keymap.set('n', 'RR', 'R', { desc = 'Replace mode' })
end)

-- 要素整形
later(function()
  require('mini.splitjoin').setup({
    mappings = {
      toggle = 'gS',
      split = 'ss',
      join = 'sj',
    },
  })
end)

-- 選択範囲の移動
later(function()
  require('mini.move').setup()
end)

-- 文字列の並べ直し
later(function()
  require('mini.align').setup()
end)

-- treesitter
now(function()
  add({
    source = 'https://github.com/nvim-treesitter/nvim-treesitter',
    hooks = {
      post_checkout = function()
        vim.cmd.TSUpdate()
      end
    },
  })
  require('nvim-treesitter').install({
    'lua', 'vim',
    'tsx', 'jsx',
    'javascript', 'typescript', 'html',
    'terraform'
  })
  -- 自動ハイライトの有効化
  vim.api.nvim_create_autocmd({ "FileType" }, {
    pattern = { 'lua', 'vim', 'javascript', 'typescript', 'html', 'typescriptreact', 'terraform' },
    callback = function()
      -- syntax highlighting, provided by Neovim
      vim.treesitter.start()
      -- folds, provided by Neovim
      vim.wo.foldexpr = "v:lua.vim.treesitter.foldexpr()"
      -- indentation, provided by nvim-treesitter
      vim.bo.indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
    end,
  })
end)

-- treesitterから、適切な形に自動コメントアウト
later(function()
  add({
    source = 'https://github.com/folke/ts-comments.nvim',
    depends = { 'nvim-treesitter/nvim-treesitter' },
  })
  require('ts-comments').setup()
end)
