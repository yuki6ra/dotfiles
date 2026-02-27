-- mini.nvimをinstall
vim.pack.add({ 'https://github.com/nvim-mini/mini.nvim' })

-- 複数ファイルで共有するためのglobal config tableを定義
_G.Config = {}

-- vim.pack + MiniMisc.safely()で遅延ロード
-- ref: https://github.com/pkazmier/nvim/blob/main/init.lua
require('mini.misc').setup()

-- package helpers
Config.now = function(f) MiniMisc.safely("now", f) end
Config.later = function(f) MiniMisc.safely("later", f) end
Config.now_if_args = vim.fn.argc(-1) > 0 and Config.now or Config.later
