{ config, pkgs, user, ... }:

{
  # Home Manager needs a bit of information about you and the paths it should
  # manage.
  home.homeDirectory = "/Users/${user}";

  home.packages = with pkgs; [
    zsh
    sheldon
    zeno
    mise
    nix
  ];

  home.file = {
    ".zshrc".source = ../../../.config/zsh/.zshrc;
    ".config/sheldon".source = ../../../.config/sheldon;
    ".config/zeno".source = ../../../.config/zeno;
    ".config/mise".source = ../../../.config/mise;
    ".config/nix".source = ../../../.config/nix;
  };

  home.sessionVariables = {
    # EDITOR = "emacs";
    GREETING = "Hello Nix";
  };
}
