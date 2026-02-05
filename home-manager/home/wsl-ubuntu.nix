{ config, pkgs, user, ... }:

{
  # Home Manager needs a bit of information about you and the paths it should
  # manage.
  home.homeDirectory = "/home/${user}";

  home.packages = with pkgs; [
    bash
  ];

  home.file = {
    ".bashrc".source = ../bash/.bashrc;
    ".profile".source = ../bash/.profile;
  };
}
