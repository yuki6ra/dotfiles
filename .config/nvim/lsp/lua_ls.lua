return {
  cmd = { 'lua-language-server' },
  filetypes = { 'lua' },
  -- ref: https://zenn.dev/ras96/articles/4d9d9493d29c06
  -- 上記記事参考に`after/lsp/lua_ls.lua`にて、vimキーワードの情報を読み込ませて警告を消す
  -- on_init = function(client)
  --   if client.workspace_folders then
  --     local path = client.workspace_folders[1].name
  --     if path ~= vim.fn.stdpath('config') and (vim.uv.fs_stat(path .. '/.luarc.json') or vim.uv.fs_stat(path .. '/.luarc.jsonc')) then
  --       return
  --     end
  --   end
  --   client.config.settings.Lua = vim.tbl_deep_extend('force', client.config.settings.Lua, {
  --     runtime = { version = 'LuaJIT' },
  --     workspace = {
  --       checkThirdParty = false,
  --       library = vim.list_extend(vim.api.nvim_get_runtime_file('lua', true), {
  --         '${3rd}/luv/library',
  --         '${3rd}/busted/library'
  --       })
  --     }
  --   })
  -- end,
  settings = {
    Lua = {
      diagnostics = {
        unusedLocalExclude = { '_*' }
      }
    }
  }
}
