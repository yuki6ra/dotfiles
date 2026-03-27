-- autocmd ====================================================================
-- configure group of autocmd for all config
local augroup = vim.api.nvim_create_augroup('init.lua', {})
-- wrapper function to use internal augroup
_G.Config.new_autocmd = function(event, opts)
  vim.api.nvim_create_autocmd(event, vim.tbl_extend('force', {
    group = augroup,
  }, opts))
end

-- bool_fn ====================================================================
_G.Config.bool_fn = setmetatable({}, {
  __index = function(_, key)
    return function(...)
      local v = vim.fn[key](...)
      if not v or v == 0 or v == '' then
        return false
      elseif type(v) == 'table' and next(v) == nil then
        return false
      end
      return true
    end
  end,
})
-- example:
-- if vim.bool_fn.has('mac') then ... end

-- Define custom `vim.pack.add()` hook helper =================================
Config.on_packchanged = function(plugin_name, kinds, callback, desc)
  local f = function(ev)
    local name, kind = ev.data.spec.name, ev.data.kind
    if not (name == plugin_name and vim.tbl_contains(kinds, kind)) then return end
    if not ev.data.active then vim.cmd.packadd(plugin_name) end
    callback()
  end
  Config.new_autocmd("PackChanged", { pattern = "*", callback = f, desc = desc })
end

