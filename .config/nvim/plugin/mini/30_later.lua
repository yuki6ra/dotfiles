local later = Config.later

-- 文字ハイライト
later(function()
  local hipatterns = require('mini.hipatterns')
  local hi_words = require('mini.extra').gen_highlighter.words
  -- ハイライトグループの追加
  vim.api.nvim_set_hl(0, 'MiniHipatternsTbd', { bg = '#656bc9', bold = true })

  hipatterns.setup({
    highlighters = {
      -- 特定の文字列をハイライト
      fixme = hi_words({ 'FIXME', 'Fixme', 'fixme' }, 'MiniHipatternsFixme'),
      hack = hi_words({ 'HACK', 'Hack', 'hack' }, 'MiniHipatternsHack'),
      todo = hi_words({ 'TODO', 'Todo', 'todo' }, 'MiniHipatternsTodo'),
      note = hi_words({ 'NOTE', 'Note', 'note' }, 'MiniHipatternsNote'),
      tbd = hi_words({ 'TBD', 'Tbd', 'tbd' }, 'MiniHipatternsTbd'),
      -- 16進数カラーコードをハイライト
      hex_color = hipatterns.gen_highlighter.hex_color(),
    }
  })
end)

-- カーソル下の単語に下線を追加
later(function()
  require('mini.cursorword').setup()
end)

-- インデントを可視化
later(function()
  require('mini.indentscope').setup()
end)

-- 行末の空白文字を可視化
later(function()
  require('mini.trailspace').setup()

  -- 行末空白を削除
  vim.api.nvim_create_user_command(
    'Trim',
    function()
      MiniTrailspace.trim()
      -- MiniTrailspace.trim_last_lines()
    end,
    { desc = 'Trim trailing space and last blank lines' }
  )
end)

later(function()
  require('mini.tabline').setup()
end)

later(function()
  require('mini.bufremove').setup()

  vim.api.nvim_create_user_command(
    'Bufdelete',
    function()
      MiniBufremove.delete()
    end,
    { desc = 'Remove buffer' }
  )
end)

-- 自動保管機能
later(function()
  require('mini.cmdline').setup()
end)

-- 移動表示を見やすくする
later(function()
  local animate = require('mini.animate')
  animate.setup({
    cursor = {
      -- Animate for 100 milliseconds with linear easing
      timing = animate.gen_timing.linear({ duration = 100, unit = 'total' }),
    },
    scroll = {
      -- Animate for 150 milliseconds with linear easing
      timing = animate.gen_timing.linear({ duration = 150, unit = 'total' }),
    }
  })
end)

-- コードマップを表示
later(function()
  local map = require('mini.map')
  map.setup({
    integrations = {
      map.gen_integration.builtin_search(),
      map.gen_integration.diff(),
      map.gen_integration.diagnostic(),
    },
    symbols = {
      scroll_line = '▶',
    }
  })
  vim.keymap.set('n', 'mmf', MiniMap.toggle_focus, { desc = 'MiniMap.toggle_focus' })
  vim.keymap.set('n', 'mms', MiniMap.toggle_side, { desc = 'MiniMap.toggle_side' })
  vim.keymap.set('n', 'mmt', MiniMap.toggle, { desc = 'MiniMap.toggle' })
end)

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

later(function()
  local function mode_nx(keys)
    return { mode = 'n', keys = keys }, { mode = 'x', keys = keys }
  end
  local clue = require('mini.clue')
  clue.setup({
    triggers = {
      -- Leader triggers
      mode_nx('<leader>'),

      -- Built-in completion
      { mode = 'i', keys = '<c-x>' },

      -- `g` key
      mode_nx('g'),

      -- Marks
      mode_nx("'"),
      mode_nx('`'),

      -- Registers
      mode_nx('"'),
      { mode = 'i', keys = '<c-r>' },
      { mode = 'c', keys = '<c-r>' },

      -- Window commands
      { mode = 'n', keys = '<c-w>' },

      -- bracketed commands
      { mode = 'n', keys = '[' },
      { mode = 'n', keys = ']' },

      -- `z` key
      mode_nx('z'),

      -- surround
      mode_nx('s'),

      -- text object
      { mode = 'x', keys = 'i' },
      { mode = 'x', keys = 'a' },
      { mode = 'o', keys = 'i' },
      { mode = 'o', keys = 'a' },

      -- option toggle (mini.basics)
      { mode = 'n', keys = 'm' },
    },

    clues = {
      -- Enhance this by adding descriptions for <Leader> mapping groups
      clue.gen_clues.builtin_completion(),
      clue.gen_clues.g(),
      clue.gen_clues.marks(),
      clue.gen_clues.registers({ show_contents = true }),
      clue.gen_clues.z(),
      clue.gen_clues.z(),
      { mode = 'n', keys = 'mm', desc = '+mini.map' },
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
    return Config.bool_fn.pumvisible() and keys.cn or keys.ct
  end, { expr = true, desc = 'Select next item if popup is visible' })
  vim.keymap.set('i', '<s-tab>', function()
    -- popup is visible -> previous item
    -- popup is NOT visible -> remove indent
    return Config.bool_fn.pumvisible() and keys.cp or keys.cd
  end, { expr = true, desc = 'Select previous item if popup is visible' })

  -- complete by <cr>
  vim.keymap.set('i', '<cr>', function()
    if not Config.bool_fn.pumvisible() then
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
  vim.keymap.set('x', '<M-Up>', '<cmd>lua MiniMove.move_selection("up")<cr>', { desc = 'MiniMove selection' })
  vim.keymap.set('x', '<M-Down>', '<cmd>lua MiniMove.move_selection("down")<cr>', { desc = 'MiniMove selection' })
  vim.keymap.set('x', '<M-Left>', '<cmd>lua MiniMove.move_selection("left")<cr>', { desc = 'MiniMove selection' })
  vim.keymap.set('x', '<M-Right>', '<cmd>lua MiniMove.move_selection("right")<cr>', { desc = 'MiniMove selection' })
  vim.keymap.set('n', '<M-Up>', '<cmd>lua MiniMove.move_line("up")<cr>', { desc = 'MiniMove line' })
  vim.keymap.set('n', '<M-Down>', '<cmd>lua MiniMove.move_line("down")<cr>', { desc = 'MiniMove line' })
  vim.keymap.set('n', '<M-Left>', '<cmd>lua MiniMove.move_line("left")<cr>', { desc = 'MiniMove line' })
  vim.keymap.set('n', '<M-Right>', '<cmd>lua MiniMove.move_line("right")<cr>', { desc = 'MiniMove line' })
end)

-- 文字列の並べ直し
later(function()
  require('mini.align').setup()
end)

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

later(function()
  require('mini.pick').setup()

  vim.ui.select = MiniPick.ui_select

  vim.keymap.set('n', '<space>f', function()
    MiniPick.builtin.files({ tool = 'git' })
  end, { desc = 'mini.pick.files' })

  vim.keymap.set('n', '<space>b', function()
    local wipeout_cur = function()
      vim.api.nvim_buf_delete(MiniPick.get_picker_matches().current.bufnr, {})
    end
    local buffer_mappings = { wipeout = { char = '<c-d>', func = wipeout_cur } }
    MiniPick.builtin.buffers({ include_current = false }, { mappings = buffer_mappings })
  end, { desc = 'mini.pick.buffers' })

  require('mini.visits').setup()
  vim.keymap.set('n', '<space>h', function()
    require('mini.extra').pickers.visit_paths()
  end, { desc = 'mini.extra.visit_paths' })

  vim.keymap.set('c', 'h', function()
    if vim.fn.getcmdtype() .. vim.fn.getcmdline() == ':h' then
      return '<c-u>Pick help<cr>'
    end
    return 'h'
  end, { expr = true, desc = 'mini.pick.help' })
end)
