local now = Config.now
local new_autocmd = Config.new_autocmd

-- theme
now(function()
  -- add({ source = 'projekt0n/github-nvim-theme' })
  -- require('github-theme').setup({
  --   options = {
  --     transparent = true,
  --   }
  -- })
  -- vim.cmd.colorscheme('github_dark')
  vim.pack.add({ 'https://gitlab.com/motaz-shokry/gruvbox.nvim' })
  require('gruvbox').setup({
    variant = "hard",
    styles = {
      transparency = true
    }
  })
  vim.cmd.colorscheme('gruvbox')

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

-- 基本的な便利な機能
now(function()
  require('mini.basics').setup({
    options = {
      extra_ui = true
    },
    mappings = {
      option_toggle_prefix = 'm',
    },
  })
end)

-- アイコン
now(function()
  require('mini.icons').setup()
end)

-- 通知
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

-- session機能 + start画面に表示
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

-- start画面
now(function()
  require('mini.starter').setup()
end)

local ms = require('mini.statusline')

ms.section_filename = function(args)
  args = args or {}
  local trunc_width = args.trunc_width or 140

  -- 幅が狭いときはデフォルト同様に短い表示
  if ms.is_truncated(trunc_width) then
    return vim.fn.fnamemodify(vim.api.nvim_buf_get_name(0), ':t')
  end

  local fullpath = vim.api.nvim_buf_get_name(0)
  if fullpath == '' then
    return ''
  end

  local home = vim.env.HOME or ''
  local ghq_root = home .. '/Documents/ghq/'

  -- ghq 管理下かどうか判定
  if fullpath:sub(1, #ghq_root) == ghq_root then
    -- ghq_root からの相対パス: host/owner/repo/...
    local rel = fullpath:sub(#ghq_root + 1)

    -- host / owner を飛ばして repo から始める
    local parts = vim.split(rel, '/', { plain = true, trimempty = true })
    if #parts >= 3 then
      -- parts[1]=host, [2]=owner, [3]=repo
      rel = table.concat(vim.list_slice(parts, 3), '/')
    end

    return rel
  end

  -- ghq 管理下以外は普通に ~ 相対 or cwd 相対で表示
  return vim.fn.fnamemodify(fullpath, ':~:.')
end

-- statusl line
now(function()
  require('mini.statusline').setup()
  vim.opt.laststatus = 3
  vim.opt.cmdheight = 0

  -- ref: https://github.com/Shougo/shougo-s-github/blob/2f1c9acacd3a341a1fa40823761d9593266c65d4/vim/rc/vimrc#L47-L49
  -- 特定の動作時にコマンドラインの高さをつける
  new_autocmd({ 'RecordingEnter', 'CmdlineEnter' }, {
    pattern = '*',
    callback = function() vim.opt.cmdheight = 1 end,
  })
  new_autocmd('RecordingLeave', {
    pattern = '*',
    callback = function() vim.opt.cmdheight = 0 end,
  })
  new_autocmd('CmdlineLeave', {
    pattern = '*',
    callback = function()
      if vim.fn.reg_recording() == '' then
        vim.opt.cmdheight = 0
      end
    end,
  })
end)

-- filer
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
      config.border, config.title_pos = 'double', 'left'
      vim.api.nvim_win_set_config(win_id, config)
    end,
  })
end)

