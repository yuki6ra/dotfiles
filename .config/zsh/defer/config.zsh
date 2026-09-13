# gitの自動補完(セキュリティチェックの日次キャッシュ化)
autoload -Uz compinit
if [[ -n ${ZDOTDIR:-$HOME}/.zcompdump(#qN.mh+24) ]]; then
  compinit
else
  compinit -C
fi

### 特殊ファイルDS_Store
# tarballへ特殊ファイルを含めないようにする
tgz() {
  if [ $# -lt 2 ]; then
    echo "Usage: tgz DIST SOURCE"
  else
    xattr -rc "${@:2}" && \
    env COPYFILE_DISABLE=1 tar zcvf "$1" --exclude=".DS_Store" "${@:2}"
  fi
}

## 補完
autoload -U +X bashcompinit && bashcompinit
complete -o nospace -C /opt/homebrew/bin/terraform terraform

# cdをzoxideでreplace
eval "$(zoxide init zsh --cmd cd)"

# mise有効化
eval "$(mise activate zsh)"

