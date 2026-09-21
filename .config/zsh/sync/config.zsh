# history
HISTFILE="$HOME/.zsh_history"
HISTSIZE=2000
SAVEHIST=2000
setopt hist_reduce_blanks   # 保存時に余分な空白を圧縮
setopt hist_ignore_all_dups # 重複を全て削除
setopt share_history        # 同時に起動しているzshで履歴を共有する
setopt inc_append_history   # 即時追記（share_history と併用）

