local now = Config.now

-- toggleterm.nvim + lazygit
now(function()
  vim.pack.add({ 'https://github.com/akinsho/toggleterm.nvim' })
  require("toggleterm").setup {}
  local Terminal = require('toggleterm.terminal').Terminal
  local lazygit  = Terminal:new({ cmd = "lazygit", direction = "float", hidden = true })

  function _lazygit_toggle()
    lazygit:toggle()
  end

  vim.api.nvim_set_keymap("n", "lg", "<cmd>lua _lazygit_toggle()<CR>", { noremap = true, silent = true })
end)
