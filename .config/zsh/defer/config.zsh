# gitの自動補完
autoload -Uz compinit && compinit

##############################
# tar
##############################

# tarballへ特殊ファイルを含めないようにする
tgz() {
  if [ $# -lt 2 ]; then
    echo "Usage: tgz DIST SOURCE"
  else
    xattr -rc "${@:2}" && \
    env COPYFILE_DISABLE=1 tar zcvf "$1" --exclude=".DS_Store" "${@:2}"
  fi
}

### path
## 補完
autoload -U +X bashcompinit && bashcompinit
complete -o nospace -C /opt/homebrew/bin/terraform terraform

# mise
eval "$(mise activate zsh)"

