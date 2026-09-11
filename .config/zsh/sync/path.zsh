# homebrew
# 社用はbrewパス生成をコメントアウト
# eval "$(/opt/homebrew/bin/brew shellenv)"

# mise
export PATH="$HOME/.local/share/mise/shims:$PATH"

# 補完
# source $(brew --prefix)/etc/bash_completion.d/az

export DOCKER_HOST="unix://${HOME}/.colima/default/docker.sock"

export PATH="$PATH:/opt/homebrew/bin"
export PATH="$PATH:/opt/homebrew/sbin"

export PATH="$HOME/.local/bin:$PATH"

