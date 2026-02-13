{ pkgs, lib,  ... }:

{
  # Necessary for using flakes on this system.
  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

  system = {
    stateVersion = 6;
    # mac のユーザー名
    # `whoami` で確認可能
    primaryUser = "yuki6ra";
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

  nixpkgs = {
    config.allowUnfree = true;
    hostPlatform = "aarch64-darwin";
  };

  homebrew = {
    enable = true;
    onActivation.cleanup = "none";
    # `brew tap` で確認可能
    taps = [
      "hashicorp/tap"
      "xwmx/taps"
    ];
    # `brew list --formula` で確認可能
    brews = [
      "awscli"
      "graphite2"
      "ripgrep"
      "azure-cli"
      "harfbuzz"
      "mise"
      "nb"
      "sheldon"
      "terraform"
      "colima"
      "docker"
      "tree"
      "bash-completion@2"
      "tree-sitter-cli"
      "ffmpeg"
      "openssl@3"
      "fzf"
      "lima"
      "yazi"
      "git"
      "gnu-time"
      "lua"
      "zoxide"
      "lua-language-server"
      "presenterm"
    ];
    # `brew list --cask` で確認可能
    casks = [
      "alt-tab"
      "discord"
      "google-chrome"
      "obsidian"
      "raycast"
      "arc"
      "font-cica"
      "microsoft-edge"
      "orbstack"
      "visual-studio-code"
      "claude"
      "ghostty"
      "notion"
      "powershell"
      "wezterm@nightly"
    ];
  };
}