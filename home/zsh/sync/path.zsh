# homebrew
#  typeset -Ug : deal with path as set of PATH
#  N-/         : add path if not exist
typeset -gU path PATH
path=(
  /opt/homebrew/bin(N-/)
  /opt/homebrew/sbin(N-/)
  /usr/bin
  /usr/sbin
  /bin
  /sbin
  /usr/local/bin(N-/)
  /usr/local/sbin(N-/)
  /Library/Apple/usr/bin
)

# volta
export VOLTA_HOME="$HOME/.volta"
export PATH="$VOLTA_HOME/bin:$PATH"

# mise
eval "$(mise activate zsh)"
export PATH="$HOME/.local/share/mise/shims:$PATH"

# gcloud
# source "$(brew --prefix)/share/google-cloud-sdk/path.zsh.inc"
# source "$(brew --prefix)/share/google-cloud-sdk/completion.zsh.inc"

# dotnet
export DOTNET_ROOT="/usr/local/share/dotnet/dotnet"
export PATH=$PATH:$DOtNET_ROOT

# binutils
export PATH="/opt/homebrew/opt/binutils/bin:$PATH"
export LDFLAGS="-L/opt/homebrew/opt/binutils/lib"
export CPPFLAGS="-I/opt/homebrew/opt/binutils/include"

# progate
export PATH=$HOME/.progate/bin:$PATH

# spaceship
# source /opt/homebrew/opt/spaceship/spaceship.zsh

# git-recover
export PATH="$HOME/dev/git-recover:$PATH"

# latex
export PATH="$PATH:/usr/local/texlive/2024/bin/universal-darwin"
export PATH="$PATH:/Library/TeX/texbin"

#########################################################
# homebrew
eval "$(/opt/homebrew/bin/brew shellenv)"

# starship
# export STARSHIP_CONFIG=~/dotfiles/home/config/starship.toml
eval "$(starship init zsh)"

# Set up fzf key bindings and fuzzy completion
source <(fzf --zsh)

# zoxide: cdの代替
eval "$(zoxide init zsh)"
