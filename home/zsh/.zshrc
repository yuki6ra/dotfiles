# zshの読み込み時間を計算するときはコメントアウトを外す
# zmodload zsh/zprof

eval "$(sheldon source)"

# zprof

# pnpm
export PNPM_HOME="/Users/powwa/Library/pnpm"
case ":$PATH:" in
  *":$PNPM_HOME:"*) ;;
  *) export PATH="$PNPM_HOME:$PATH" ;;
esac
# pnpm end

