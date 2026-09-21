# gitの自動補完(セキュリティチェックの日次キャッシュ化)
autoload -Uz compinit
if [[ -n ${ZDOTDIR:-$HOME}/.zcompdump(#qN.mh+24) ]]; then
  compinit
else
  compinit -C
fi

# autoload -U +X bashcompinit && bashcompinit
# complete -o nospace -C /opt/homebrew/bin/terraform terraform

if command -v zoxide >/dev/null 2>&1; then
  eval "$(zoxide init zsh --cmd cd)"
fi
