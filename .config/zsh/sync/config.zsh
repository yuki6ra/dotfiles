# 新しいコマンドを即認識させる
zstyle ":completion:*:commands" rehash 1

# ファイル名補完後にスペースを消さない
export ZLE_REMOVE_SUFFIX_CHARS=$''

# history
export HISTFILE=~/.zsh_history
export HISTSIZE=2000
export SAVEHIST=2000
setopt hist_reduce_blanks   # 保存時に余分な空白を圧縮
setopt hist_ignore_all_dups # 重複を全て削除
setopt hist_verify          # !!展開時に即実行しない
setopt share_history        # 同時に起動しているzshで履歴を共有する
setopt extended_history     # タイムスタンプ記録
setopt inc_append_history   # 即時追記（share_history と併用）

# nix
# . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh

