local later, now_if_args = Config.later, Config.now_if_args

-- treesitter
now_if_args(function()
  local ts_update = function() vim.cmd("TSUpdate") end
  Config.on_packchanged("nvim-treesitter", { "update" }, ts_update, "Update tree-sitter parsers")
  vim.pack.add({
    'https://github.com/nvim-treesitter/nvim-treesitter',
    {
      src = 'https://github.com/nvim-treesitter/nvim-treesitter',
      version = 'main'
    }
  })
require("nvim-treesitter").setup({})
  require('nvim-treesitter').install({
    'lua', 'vim',
    'tsx', 'jsx',
    'javascript', 'typescript', 'html',
    'terraform', 'bash',
    'nix'
  })
  -- 自動ハイライトの有効化
  vim.api.nvim_create_autocmd({ "FileType" }, {
    pattern = { 'lua', 'vim', 'javascript', 'typescript', 'html', 'typescriptreact', 'terraform', 'bash', 'nix' },
    callback = function()
      -- syntax highlighting, provided by Neovim
      vim.treesitter.start()
      -- folds, provided by Neovim
      vim.wo.foldexpr = "v:lua.vim.treesitter.foldexpr()"
      -- indentation, provided by nvim-treesitter
      vim.bo.indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
    end,
  })
  vim.treesitter.language.register("bash", { "sh", "zsh" })

  -- ref: https://mise.jdx.dev/mise-cookbook/neovim.html#syntax-highlighting
  require("vim.treesitter.query").add_predicate("is-mise?", function(_, _, bufnr, _)
    local filepath = vim.api.nvim_buf_get_name(tonumber(bufnr) or 0)
    local filename = vim.fn.fnamemodify(filepath, ":t")
    return string.match(filename, ".*mise.*%.toml$") ~= nil
  end, { force = true, all = false })
end)

-- treesitterから、適切な形に自動コメントアウト
later(function()
  vim.pack.add({ 'https://github.com/folke/ts-comments.nvim' })
  require('ts-comments').setup()
end)

-- vim-jp/vimdoc-ja
-- vimの日本語ヘルプ
later(function()
  vim.pack.add({ 'https://github.com/vim-jp/vimdoc-ja' })
  -- prefer Jaganese as the help language
  vim.opt.helplang:prepend('ja')
end)

