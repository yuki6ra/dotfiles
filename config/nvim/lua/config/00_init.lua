-- Setup mini.deps
-- Clone 'mini.nvim' manually in a way that it gets managed by 'mini.deps'
local path_package = vim.fn.stdpath('data') .. '/site/'
local mini_path = path_package .. 'pack/deps/start/mini.nvim'

if not vim.loop.fs_stat(mini_path) then
  vim.cmd('echo "Installing `mini.nvim`" | redraw')
  local clone_cmd = {
    'git', 'clone', '--filter=blob:none',
    'https://github.com/echasnovski/mini.nvim', mini_path
  }
  vim.fn.system(clone_cmd)
  vim.cmd('packadd mini.nvim | helptags ALL')
  vim.cmd('echo "Installed `mini.nvim`" | redraw')
end

-- Set up 'mini.deps' (cusbool_fntomize to your liking)
require('mini.deps').setup({ path = { package = path_package } })

-- Export helpers
_G.MiniDeps = require('mini.deps')
local add, now, later = MiniDeps.add, MiniDeps.now, MiniDeps.later

-- mini.basics
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

-- Load plugin configurations
require('config.ui')      -- UI系プラグイン
require('config.edit')    -- 編集系プラグイン
require('config.nav')     -- ナビゲーション系プラグイン
require('config.git')     -- Git系プラグイン
require('config._options')