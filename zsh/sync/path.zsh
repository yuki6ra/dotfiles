##############################
# eval
##############################

# homebrew
eval "$(/opt/homebrew/bin/brew shellenv)"
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