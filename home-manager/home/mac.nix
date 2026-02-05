{ config, pkgs, user, ... }:

{
  # Home Manager needs a bit of information about you and the paths it should
  # manage.
  home.homeDirectory = "/Users/${user}";

  home.packages = with pkgs; [
    zsh
  ];

  home.file = {
    ".zshrc".source = ../../.config/zsh/.zshrc;
  };

  home.sessionVariables = {
    # EDITOR = "emacs";
    GREETING = "Hello Nix";
  };
}
