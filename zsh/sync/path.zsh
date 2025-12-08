##############################
# eval
##############################

# homebrew
# 社用はbrewパス生成をコメントアウト
#eval "$(/opt/homebrew/bin/brew shellenv)"
# mise
eval "$(mise activate zsh)"

##############################
# path
##############################

# mise
export PATH="$HOME/.local/share/mise/shims:$PATH"

# 補完
autoload -U +X bashcompinit && bashcompinit
complete -o nospace -C /opt/homebrew/bin/terraform terraform
source $(brew --prefix)/etc/bash_completion.d/az

# 社用はcolimaを必ず使う
export DOCKER_HOST="unix://${HOME}/.colima/default/docker.sock"
