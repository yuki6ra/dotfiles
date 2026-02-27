##############################
# eval
##############################

# homebrew
# 社用はbrewパス生成をコメントアウト
# eval "$(/opt/homebrew/bin/brew shellenv)"
# mise
eval "$(mise activate zsh)"

##############################
# path
##############################

# mise
# export PATH="$HOME/.local/share/mise/shims:$PATH"

# 補完
autoload -U +X bashcompinit && bashcompinit
complete -o nospace -C /opt/homebrew/bin/terraform terraform
# source $(brew --prefix)/etc/bash_completion.d/az

# 社用はcolimaを必ず使う
export DOCKER_HOST="unix://${HOME}/.colima/default/docker.sock"

# 社用はopensslにpathが必要
# export PATH="/opt/homebrew/opt/openssl@3/bin:$PATH"
# export LDFLAGS="-L/opt/homebrew/opt/openssl@3/lib"
# export CPPFLAGS="-I/opt/homebrew/opt/openssl@3/include"

# Added by OrbStack: command-line tools and integration
# This won't be added again if you remove it.
# source ~/.orbstack/shell/init.zsh 2>/dev/null || :
# cdをzoxideでreplace
eval "$(zoxide init zsh --cmd cd)"

