-- configure group of autocmd for all config
local augroup = vim.api.nvim_create_augroup('init.lua', {})

-- wrapper function to use internal augroup
local function create_autocmd(event, opts)
  vim.api.nvim_create_autocmd(event, vim.tbl_extend('force', {
    group = augroup,
  }, opts))
end

-- Export for use in other modules
return {
  create_autocmd = create_autocmd,
  augroup = augroup,
}