# デフォルト設定
# ref: https://github.com/yuki-yano/zeno.zsh/blob/main/README.ja.md#%E8%A8%AD%E5%AE%9A%E4%BE%8B
export ZENO_HOME=~/.config/zeno

  ## ^m: Ctrl+m または Enter
  ## ^i: Tab
if [[ -n $ZENO_LOADED ]]; then
  bindkey ' '  zeno-auto-snippet

  # snippet が一致しなかった場合の fallback（デフォルト: self-insert）
  # export ZENO_AUTO_SNIPPET_FALLBACK=self-insert

  # zsh の incremental search を使っている場合
  # bindkey -M isearch ' ' self-insert

  bindkey '^m' zeno-auto-snippet-and-accept-line

  bindkey '^i' zeno-completion

  bindkey '^xx' zeno-insert-snippet           # snippet picker（fzf）を開いてカーソル位置へ挿入

  bindkey '^x '  zeno-insert-space
  bindkey '^x^m' accept-line
  bindkey '^x^z' zeno-toggle-auto-snippet

  # preprompt の bind
  bindkey '^xp' zeno-preprompt
  bindkey '^xs' zeno-preprompt-snippet
  # ZLE 外では `zeno-preprompt git {{cmd}}` や `zeno-preprompt-snippet foo`
  # を実行して次の prompt prefix を設定できます。空引数で呼ぶと状態をリセットします。

  bindkey '^r' zeno-history-selection         # 従来の history widget
  # bindkey '^r' zeno-smart-history-selection # smart history widget

  # completion が一致しなかった場合の fallback
  # （デフォルト: あれば fzf-completion、なければ expand-or-complete）
  # export ZENO_COMPLETION_FALLBACK=expand-or-complete
fi

