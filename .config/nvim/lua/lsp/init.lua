vim.api.nvim_create_user_command(
  'LspHealth',
  'checkhealth vim.lsp',
  { desc = 'LSP health check' }
)

vim.diagnostic.config({
  virtual_text = true
})

-- augroup for this config file
local augroup = vim.api.nvim_create_augroup('lsp/init.lua', {})

vim.api.nvim_create_autocmd('LspAttach', {
  group = augroup,
  callback = function(args)
    local client = assert(vim.lsp.get_client_by_id(args.data.client_id))

    -- definition jump command
    if client:supports_method('textDocument/definition') then
      vim.keymap.set('n', 'grd', function()
        vim.lsp.buf.definiiton()
      end, { buffer = args.buf, desc = 'vim.lsp.buf.definition()' })
    end

    -- format command
    if client:supports_method('textDocument/formatting') then
      vim.keymap.set('n', '<space>i', function()
        vim.lsp.buf.format({ bufnr = args.buf, id = client.id })
      end, { buffer = args.buf, desc = 'Format buffer' })
    end
  end,
})

vim.lsp.config('*', {
  root_markers = { '.git' },
  capabilities = require('mini.completion').get_lsp_capabilities(),
})

-- lspファイル自動読み込み
-- このファイルの存在するディレクトリ
local dirname = vim.fn.stdpath('config') .. '/lua/lsp'

-- 設定したlspを保存する配列
local lsp_names = {}

-- 同一ディレクトリのファイルをループ
for file, ftype in vim.fs.dir(dirname) do
  -- `.lua`で終わるファイルを処理（init.luaは除く）
  if ftype == 'file' and vim.endswith(file, '.lua') and file ~= 'init.lua' then
    -- 拡張子を除いてlsp名を作る
    local lsp_name = file:sub(1, -5) -- fname without '.lua'
    -- 読み込む
    local ok, result = pcall(require, 'lsp.' .. lsp_name)
    if ok then
      -- 読み込めた場合はlspを設定
      vim.lsp.config(lsp_name, result)
      table.insert(lsp_names, lsp_name)
    else
      -- 読み込めなかった場合はエラーを表示
      vim.notify('Error loading LSP: ' .. lsp_name .. '\n' .. result, vim.log.levels.WARN)
    end
  end
end

-- 読み込めたlspを有効化
vim.lsp.enable(lsp_names)
