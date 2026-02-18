{ pkgs, lib,  ... }:

{
  system = {
    primaryUser = "yuki6ra";
    stateVersion = 6;
    defaults = {
      finder = {
        AppleShowAllExtensions = true;  # ファイル拡張子を表示
        AppleShowAllFiles = true;    # 隠しファイルを表示
        FXEnableExtensionChangeWarning = false; # 拡張子変更の警告を無効化
        ShowPathbar = true;  # パスバーを表示
        ShowStatusBar = true;  # ステータスバーを表示
      };
      dock = {
        autohide = true;  # Dockを自動的に隠す
        show-recents = false; # 最近使ったアプリを非表示
        tilesize = 36; # Dockのアイコンサイズ
        magnification = true; # Dockの拡大表示を有効化
        orientation = "bottom"; # Dockの位置(bottom / left / right)
        launchanim = false; # アプリ起動時のアニメーションを無効化
      };
    };
  };

  # Necessary for using flakes on this system.
  # nix.settings.experimental-features = [
  #   "nix-command"
  #   "flakes"
  # ];

  nixpkgs = {
    config.allowUnfree = true;
    hostPlatform = "aarch64-darwin";
  };

  homebrew = {
    enable = true;
    onActivation.cleanup = "uninstall";
    taps = [
      "hashicorp/tap"
      "xwmx/taps"
    ];
    brews = [
      "openssl@3"
      "awscli"
      "azure-cli"
      "bash-completion@2"
      "lima"
      "colima"
      "docker"
      "docker-compose"
      "fd"
      "ffmpeg"
      "fzf"
      "gcc"
      "git"
      "gnu-time"
      "graphite2"
      "harfbuzz"
      "imagemagick"
      "lua"
      "lua-language-server"
      "mise"
      "neovim"
      "poppler"
      "presenterm"
      "resvg"
      "ripgrep"
      "sevenzip"
      "sheldon"
      "telnet"
      "tree"
      "tree-sitter-cli"
      "yazi"
      "zoxide"
      "hashicorp/tap/terraform"
      "hashicorp/tap/terraform-ls"
      "xwmx/taps/nb"
    ];
    casks = [
      # "arc"
      # "claude"
      "discord"
      "font-cica"
      "ghostty"
      "google-chrome"
      "microsoft-edge"
      "notion"
      "obsidian"
      # "orbstack"
      "powershell"
      "raycast"
      "visual-studio-code"
    ];
  };
}