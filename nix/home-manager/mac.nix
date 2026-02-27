{ config, pkgs, lib, user, ... }:

{
  # Home Manager needs a bit of information about you and the paths it should manage.
  home.homeDirectory = "/Users/${user}";

  home.packages = with pkgs; [
    # gnu-time # linux time, macのみで良さそう
    colima
  ];

  home.file = {
  };

  # ref: https://www.reddit.com/r/NixOS/comments/1bh7vy8/does_anyone_have_a_working_example_of_a/?tl=ja
  launchd.agents.colima = {
    enable = true;
    config = {
      RunAtLoad = true;
      EnvironmentVariables.PATH = lib.makeBinPath ([ pkgs.docker ] ++ [ "/usr" ]);
      ProgramArguments = [ (lib.getExe pkgs.colima) "start" "-f" ];
      StandardErrorPath = "${config.home.homeDirectory}/.tmp/colima.err.log";
      StandardOutPath = "${config.home.homeDirectory}/.tmp/colima.out.log";
    };
  };
}
