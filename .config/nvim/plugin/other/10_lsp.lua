local later = Config.later

local function get_filename_list(dir_name)
  local dirname = vim.fn.stdpath('config') .. dir_name
  local list = {}

  for file, ftype in vim.fs.dir(dirname) do
    if ftype == 'file' and vim.endswith(file, '.lua') and file ~= 'init.lua' then
      local lsp_name = file:sub(1, -5)

      local path = dirname .. '/' .. file
      local ok, chunk = pcall(loadfile, path)
      if not ok or not chunk then
        vim.notify('Error loading LSP file: ' .. path .. '\n' .. tostring(chunk), vim.log.levels.WARN)
      else
        local ok2, result = pcall(chunk)
        if ok2 then
          vim.lsp.config(lsp_name, result)
          table.insert(list, lsp_name)
        else
          vim.notify('Error running LSP file: ' .. path .. '\n' .. tostring(result), vim.log.levels.WARN)
        end
      end
    end
  end

  return list
end


later(function()
  -- 診断の共通設定
  vim.diagnostic.config({
    virtual_text = true,
  })

  -- LspAttach keymap
  local augroup = vim.api.nvim_create_augroup('user-lsp', {})

  vim.api.nvim_create_autocmd('LspAttach', {
    group = augroup,
    callback = function(args)
      local client = assert(vim.lsp.get_client_by_id(args.data.client_id))

      if client:supports_method('textDocument/definition') then
        vim.keymap.set('n', 'grd', function()
          vim.lsp.buf.definition()
        end, { buffer = args.buf, desc = 'vim.lsp.buf.definition()' })
      end

      if client:supports_method('textDocument/formatting') then
        vim.keymap.set('n', '<space>i', function()
          vim.lsp.buf.format({ bufnr = args.buf, id = client.id })
        end, { buffer = args.buf, desc = 'Format buffer' })
      end
    end,
  })

  -- 全サーバー共通のデフォルト設定
  vim.lsp.config('*', {
    root_markers = { '.git' },
    capabilities = require('mini.completion').get_lsp_capabilities(),
  })

  local lsp_names = get_filename_list('/lsp')

  -- 有効にしたいサーバーを列挙
  vim.lsp.enable(lsp_names)
end)

