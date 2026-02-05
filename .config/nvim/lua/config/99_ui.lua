local add, now, later = MiniDeps.add, MiniDeps.now, MiniDeps.later
local autocmds = require('utils.autocmd')

-- アイコン有効化
now(function()
  require('mini.icons').setup()
end)

-- ステータスライン
now(function()
  require('mini.statusline').setup()
  vim.opt.laststatus = 3
  vim.opt.cmdheight = 0

  -- ref: https://github.com/Shougo/shougo-s-github/blob/2f1c9acacd3a341a1fa40823761d9593266c65d4/vim/rc/vimrc#L47-L49
  -- 特定の動作時にコマンドラインの高さをつける
  autocmds.create_autocmd({ 'RecordingEnter', 'CmdlineEnter' }, {
    pattern = '*',
    callback = function() vim.opt.cmdheight = 1 end,
  })
  autocmds.create_autocmd('RecordingLeave', {
    pattern = '*',
    callback = function() vim.opt.cmdheight = 0 end,
  })
  autocmds.create_autocmd('CmdlineLeave', {
    pattern = '*',
    callback = function()
      if vim.fn.reg_recording() == '' then
        vim.opt.cmdheight = 0
      end
    end,
  })
end)

-- 通知をウィンドウに表示
now(function()
  local mini_notify = require('mini.notify')
  mini_notify.setup({
    window = {
      winblend = 0,
    }
  })

  vim.notify = mini_notify.make_notify({
    -- ERROR = { duratin = 10000 }
  })

  -- 過去の通知を確認
  vim.api.nvim_create_user_command('NotifyHistory', function()
    MiniNotify.show_history()
  end, { desc = 'Show Notify History' })
end)

-- 文字ハイライト
later(function()
  local hipatterns = require('mini.hipatterns')
  local hi_words = require('mini.extra').gen_highlighter.words
  hipatterns.setup({
    highlighters = {
      -- 特定の文字列をハイライト
      fixme = hi_words({ 'FIXME', 'Fixme', 'fixme' }, 'MiniHipatternsFixme'),
      hack = hi_words({ 'HACK', 'Hack', 'hack' }, 'MiniHipatternsHack'),
      todo = hi_words({ 'TODO', 'Todo', 'todo' }, 'MiniHipatternsTodo'),
      note = hi_words({ 'NOTE', 'Note', 'note' }, 'MiniHipatternsNote'),
      -- 16進数カラーコードをハイライト
      hex_color = hipatterns.gen_highlighter.hex_color(),
    }
  })
end)

-- 表示増強系
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

-- vim-jp/vimdoc-ja
-- vimの日本語ヘルプ
later(function()
  add('https://github.com/vim-jp/vimdoc-ja')
  -- prefer Jaganese as the help language
  vim.opt.helplang:prepend('ja')
end)

-- カラースキーム
now(function()
  -- add({ source = 'projekt0n/github-nvim-theme' })
  -- require('github-theme').setup({
  --   options = {
  --     transparent = true,
  --   }
  -- })
  -- vim.cmd.colorscheme('github_dark')
  add({ source = 'masisz/wisteria.nvim' })
  require('wisteria').setup({
    options = {
      transparent = true
    }
  })
  vim.cmd.colorscheme('wisteria')

  require('mini.colors').get_colorscheme():resolve_links():add_transparency({
    general = true,
    float = true,
    statuscolumn = true,
    statusline = true,
    tabline = true,
    winbar = true
  }):apply()
  -- floating window to transparency
  vim.o.winblend = 0
  vim.o.pumblend = 30
end)
