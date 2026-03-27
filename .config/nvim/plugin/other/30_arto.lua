Config.later(function ()
  vim.pack.add({ 'https://github.com/arto-app/arto.vim' })
  -- nixでinstallしたaartoの場所
  vim.g.arto_path = vim.fn.expand('~/Applications/Arto.app')
end)

