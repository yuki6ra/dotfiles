-- tsserver.lua
return {
  -- 使用する LSP サーバーのコマンド
  -- 例: npm i -g typescript-language-server typescript
  cmd = { 'typescript-language-server', '--stdio' },

  -- 対象にするファイルタイプ
  filetypes = {
    'typescript',
    'typescriptreact',
    'tsx',
    'javascript',
    'javascriptreact',
  },

  -- プロジェクトルートの判定に使うファイル
  root_dir = function(fname)
    local util = require('lspconfig.util')
    return util.root_pattern('tsconfig.json', 'jsconfig.json', 'package.json', '.git')(fname)
      or util.path.dirname(fname)
  end,

  on_init = function(client)
    -- Neovim の設定ディレクトリ内ではグローバル設定を使いたい
    -- それ以外のプロジェクトでは tsconfig/jsconfig があればそちらを優先
    if client.workspace_folders then
      local path = client.workspace_folders[1].name

      -- Neovim の config ディレクトリかどうか
      local is_nvim_config = (path == vim.fn.stdpath('config'))

      -- プロジェクトに TypeScript/JS 関連の設定ファイルがあるかどうか
      local has_ts_js_config =
        vim.uv.fs_stat(path .. '/tsconfig.json')
        or vim.uv.fs_stat(path .. '/jsconfig.json')
        or vim.uv.fs_stat(path .. '/package.json')

      -- Neovim config 以外で tsconfig/jsconfig/package.json がある場合は、
      -- プロジェクト固有の設定に任せる（ここでの上書きは行わない）
      if not is_nvim_config and has_ts_js_config then
        return
      end
    end

    -- client.config.settings を安全に初期化
    client.config.settings = client.config.settings or {}

    -- ここで TypeScript/JavaScript 用のデフォルト設定をマージする
    -- 必要に応じて好みの設定に変えてください
    local new_settings = {
      typescript = {
        format = {
          semicolons = 'insert', -- 'insert' | 'remove' | 'ignore'
        },
        inlayHints = {
          includeInlayParameterNameHints = 'all',
          includeInlayParameterNameHintsWhenArgumentMatchesName = false,
          includeInlayFunctionParameterTypeHints = true,
          includeInlayVariableTypeHints = true,
          includeInlayVariableTypeHintsWhenTypeMatchesName = false,
          includeInlayPropertyDeclarationTypeHints = true,
          includeInlayFunctionLikeReturnTypeHints = true,
          includeInlayEnumMemberValueHints = true,
        },
      },
      javascript = {
        format = {
          semicolons = 'insert',
        },
        inlayHints = {
          includeInlayParameterNameHints = 'all',
          includeInlayParameterNameHintsWhenArgumentMatchesName = false,
          includeInlayFunctionParameterTypeHints = true,
          includeInlayVariableTypeHints = true,
          includeInlayVariableTypeHintsWhenTypeMatchesName = false,
          includeInlayPropertyDeclarationTypeHints = true,
          includeInlayFunctionLikeReturnTypeHints = true,
          includeInlayEnumMemberValueHints = true,
        },
      },
      -- 共通の設定例（必要に応じて）
      completions = {
        completeFunctionCalls = true,
      },
    }

    client.config.settings = vim.tbl_deep_extend(
      'force',
      client.config.settings,
      new_settings
    )
  end,

  -- tsserver は Lua のような diagnostics.unusedLocalExclude 形式ではないので、
  -- ここには必要なものだけを記述します（例として inlayHints を再掲）。
  settings = {
    typescript = {
      inlayHints = {
        includeInlayParameterNameHints = 'all',
        includeInlayParameterNameHintsWhenArgumentMatchesName = false,
        includeInlayFunctionParameterTypeHints = true,
        includeInlayVariableTypeHints = true,
        includeInlayVariableTypeHintsWhenTypeMatchesName = false,
        includeInlayPropertyDeclarationTypeHints = true,
        includeInlayFunctionLikeReturnTypeHints = true,
        includeInlayEnumMemberValueHints = true,
      },
    },
    javascript = {
      inlayHints = {
        includeInlayParameterNameHints = 'all',
        includeInlayParameterNameHintsWhenArgumentMatchesName = false,
        includeInlayFunctionParameterTypeHints = true,
        includeInlayVariableTypeHints = true,
        includeInlayVariableTypeHintsWhenTypeMatchesName = false,
        includeInlayPropertyDeclarationTypeHints = true,
        includeInlayFunctionLikeReturnTypeHints = true,
        includeInlayEnumMemberValueHints = true,
      },
    },
  },
}
