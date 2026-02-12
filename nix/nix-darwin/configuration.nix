{ pkgs, lib,  ... }:

{
  # Necessary for using flakes on this system.
  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
    "pipe-operators"
  ];

  system = {
    stateVersion = 6;
    # mac のユーザー名
    # `whoami` で確認可能
    primaryUser = "yuki6ra";
  };

  nixpkgs = {
    config.allowUnfree = true;
    hostPlatform = "aarch64-darwin";
  };

  homebrew = {
    enable = true;
    onActivation.cleanup = "none";
    # `brew tap` で確認可能
    taps = [ ];
    # `brew list --formula` で確認可能
    brews = [
      "git"
      "gnu-time"
    ];
    # `brew list --cask` で確認可能
    casks = [
      "claude"
      "visual-studio-code"
    ];
  };
}