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
