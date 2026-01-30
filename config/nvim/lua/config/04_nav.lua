local add, now, later = MiniDeps.add, MiniDeps.now, MiniDeps.later
require('utils.user_command')

-- vimのsession機能とstarterを連携
now(function()
  require('mini.sessions').setup()

  -- `:SessionWrite`: セッションの保存
  local function is_blank(arg)
    return arg == nil or arg == ''
  end
  local function get_sessions(lead)
    -- ref: https://qiita.com/delphinus/items/2c993527df40c9ebaea7
    return vim
        .iter(vim.fs.dir(MiniSessions.config.directory))
        :map(function(v)
          local name = vim.fs.basename(v)
          return vim.startswith(name, lead) and name or nil
        end)
        :totable()
  end
  vim.api.nvim_create_user_command('SessionWrite', function(arg)
    local session_name = is_blank(arg.args) and vim.v.this_session or arg.args
    if is_blank(session_name) then
      vim.notify('No session name specified', vim.log.levels.WARN)
      return
    end
    vim.cmd('%argdelete')
    MiniSessions.write(session_name)
  end, { desc = 'Write session', nargs = '?', complete = get_sessions })

  -- `:SessionDelete`: セッションの削除
  vim.api.nvim_create_user_command('SessionDelete', function(arg)
    MiniSessions.select('delete', { force = arg.bang })
  end, { desc = 'Delete session', bang = true })

  -- `:SessionLoad`: 保存済みセッションを読み込む
  vim.api.nvim_create_user_command('SessionLoad', function()
    MiniSessions.select('read', { verbose = true })
  end, { desc = 'Load session' })

  -- `:SessionEscape`: 現在のセッションから離脱
  vim.api.nvim_create_user_command('SessionEscape', function()
    vim.v.this_session = ''
  end, { desc = 'Escape session' })

  -- `:SessionReveal`: 現在のセッションを表示
  vim.api.nvim_create_user_command('SessionReveal', function()
    if is_blank(vim.v.this_session) then
      vim.print('No session')
      return
    end
    vim.print(vim.fs.basename(vim.v.this_session))
  end, { desc = 'Reveal session' })
end)

-- スタート画面でファイル・セッション選択
now(function()
  require('mini.starter').setup()
end)

-- キーマップのhelp表示
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

-- バッファをtab表示
later(function()
  require('mini.tabline').setup()
end)

-- ウィンドウ構成を保ったままバッファ削除
later(function()
  require('mini.bufremove').setup()
  -- `:bdelete` -> `:Bufdelete`
  vim.api.nvim_create_user_command(
    'Bufdelete',
    function()
      MiniBufremove.delete()
    end,
    { desc = 'Remove buffer' }
  )
end)

-- ファイル選択支援系
-- ファイラ
now(function()
  require('mini.files').setup({})

  vim.api.nvim_create_user_command(
    'Files',
    function()
      MiniFiles.open()
    end,
    { desc = 'Open file exproler' }
  )
  vim.keymap.set('n', '<space>e', '<cmd>Files<cr>', { desc = 'Open file exproler' })

  -- customize window
  vim.api.nvim_create_autocmd('User', {
    pattern = 'MiniFilesWindowOpen',
    callback = function(args)
      local win_id = args.data.win_id

      -- ウィンドウ固有の設定をカスタマイズ
      vim.wo[win_id].winblend = 0
      local config = vim.api.nvim_win_get_config(win_id)
      config.border, config.title_pos = 'double', 'right'
      vim.api.nvim_win_set_config(win_id, config)
    end,
  })
end)

-- Fuzzy Finder
later(function()
  require('mini.pick').setup()

  -- vim.ui.selectの上書き
  vim.ui.select = MiniPick.ui_select

  -- ファイルピッカーを開く
  vim.keymap.set('n', '<space>f', function()
    MiniPick.builtin.files({ tool = 'git' })
  end, { desc = 'mini.pick.files' })

  -- バッファをFuzzy Find
  vim.keymap.set('n', '<space>b', function()
    local wipeout_cur = function()
      vim.api.nvim_buf_delete(MiniPick.get_picker_matches().current.bufnr, {})
    end
    local buffer_mappings = { wipeout = { char = '<c-d>', func = wipeout_cur } }
    MiniPick.builtin.buffers({ include_current = false }, { mappings = buffer_mappings })
  end, { desc = 'mini.pick.buffers' })

  -- 直近に開いたファイルをFuzzy Find
  require('mini.visits').setup()
  vim.keymap.set('n', '<space>h', function()
    require('mini.extra').pickers.visit_paths()
  end, { desc = 'mini.extra.visit_paths' })

  -- ヘルプをFuzzy Find
  vim.keymap.set('c', 'h', function()
    if vim.fn.getcmdtype() .. vim.fn.getcmdline() == ':h' then
      return '<c-u>Pick help<cr>'
    end
    return 'h'
  end, { expr = true, desc = 'mini.pick.help' })
end)

-- 移動支援系
-- デフォルトの移動(`f`, `t`)を強化
later(function()
  require('mini.jump').setup({
    delay = {
      idle_stop = 10,
    },
  })
end)

-- 画面内のどこへでも移動
later(function()
  require('mini.jump2d').setup()
end)

-- `[`, `]`によるキーマップの拡充
later(function()
  require('mini.bracketed').setup()
end)

-- quickfixの活用
later(function()
  -- 内部grep
  vim.keymap.set('n', '?', '<cmd>silent vimgrep//gj%|copen<cr>',
    { desc = 'Populate latest search result to quickfix list' })

  -- use rg for 外部grep
  vim.opt.grepprg = table.concat({
    'rg',
    '--vimgrep',
    '--trim',
    '--hidden',
    [[--glob='!.git']],
    [[--glob='!*.lock']],
    [[--glob='!*-lock.json']],
    [[--glob='!*generated*']],
  }, ' ')
  vim.opt.grepformat = '%f:%l:%c:%m'

  -- ref: `:NewGrep` in `:help grep`
  vim.api.nvim_create_user_command('Grep', function(arg)
    local grep_cmd = 'silent grep! '
        .. (arg.bang and '--fixed-strings -- ' or '')
        .. vim.fn.shellescape(arg.args, true)
    vim.cmd(grep_cmd)
    if vim.fn.getqflist({ size = true }).size > 0 then
      vim.cmd.copen()
    else
      vim.notify('no matches found', vim.log.levels.WARN)
      vim.cmd.cclose()
    end
  end, { nargs = '+', bang = true, desc = 'Enhounced grep' })

  vim.keymap.set('n', '<space>/', ':Grep ', { desc = 'Grep' })
  vim.keymap.set('n', '<space>?', ':Grep <c-r><c-w>', { desc = 'Grep current word' })
end)

-- quickfixリストから直接編集
later(function()
  add({ source = 'https://github.com/stevearc/quicker.nvim' })
  local quicker = require('quicker')
  vim.keymap.set('n', 'mq', function()
    quicker.toggle()
    quicker.refresh()
  end, { desc = 'Toggle quickfix' })
  quicker.setup({
    keys = {
      {
        '>',
        function()
          require('quicker').expand({ before = 2, after = 2, add_to_existing = true })
        end,
        desc = 'Expand quickfix context',
      },
      {
        '<',
        function()
          require('quicker').collapse()
        end,
        desc = 'Collapse quickfix context',
      },
    },
  })
end)
