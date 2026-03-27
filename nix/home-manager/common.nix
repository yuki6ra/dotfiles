{ config, pkgs, user, inputs, ... }:

{
  nixpkgs = {
    # overlays = [
    #   inputs.neovim.overlays.default;
    # ];
    config = {
      allowUnfree = true;
    };
  };
  # Home Manager needs a bit of information about you and the paths it should
  # manage.
  home.username = user;

  # This value determines the Home Manager release that your configuration is
  # compatible with. This helps avoid breakage when a new Home Manager release
  # introduces backwards incompatible changes.
  #
  # You should not change this value, even if you update Home Manager. If you do
  # want to update the value, then make sure to first check the Home Manager
  # release notes.
  home.stateVersion = "25.11"; # Please read the comment before changing.

  # The home.packages option allows you to install Nix packages into your
  # environment.
  home.packages = with pkgs; [
    # # Adds the 'hello' command to your environment. It prints a friendly
    # # "Hello, world!" when run.
    # pkgs.hello
    ## shell configuration
    zsh # default shell
    sheldon # zsh/bash plugin manager

    ## tools
    git
    lazygit
    delta
    ghq
    neovim # nighly
    yazi # file manager
    zoxide # super cd, required zeno / yazi
    fzf # fuzzy finder, required zeno / yazi
    fd # search file, required yazi
    ripgrep # super grep, required nvim / yazi
    jq # json processer, required yazi(option)
    resvg # svg preview, required yazi(option)
    imagemagick # jpg preview, required yazi(option)
    nb # cli note-taking
    presenterm # presentation on terminal
    # tree
    openssl

    ## develop
    mise
    docker
    docker-compose
    terraform
    terraform-ls
    azure-cli
    awscli
    # tree-sitter-cli これはnpmでinsltallする

    # # It is sometimes useful to fine-tune packages, for example, by applying
    # # overrides. You can do that directly here, just don't forget the
    # # parentheses. Maybe you want to install Nerd Fonts with a limited number of
    # # fonts?
    # (pkgs.nerdfonts.override { fonts = [ "FantasqueSansMono" ]; })

    # # You can also create simple shell scripts directly inside your
    # # configuration. For example, this adds a command 'my-hello' to your
    # # environment:
    # (pkgs.writeShellScriptBin "my-hello" ''
    #   echo "Hello, ${config.home.username}!"
    # '')
  ];

  # Home Manager is pretty good at managing dotfiles. The primary way to manage
  # plain files is through 'home.file'.
  home.file = {
    # # Building this configuration will create a copy of 'dotfiles/screenrc' in
    # # the Nix store. Activating the configuration will then make '~/.screenrc' a
    # # symlink to the Nix store copy.
    # ".screenrc".source = dotfiles/screenrc;
    ## shell
    ".zshrc".source = ../../.config/zsh/.zshrc;
    ".config/sheldon".source = ../../.config/sheldon;
    ".config/nix".source = ../../.config/nix;

    ## tools
    ".gitconfig".source = ../../.config/git/.gitconfig;
    # ".config/nvim".source =  ../../.config/nvim;
    ".config/zeno".source = ../../.config/zeno;
    ".config/yazi".source = ../../.config/yazi;
    ".config/lazygit".source = ../../.config/lazygit;
    ".nbrc".source = ../../.config/nb/.nbrc;
    ".config/nvim".source = config.lib.file.mkOutOfStoreSymlink "${builtins.toString config.home.homeDirectory}/Documents/dotfiles/.config/nvim";

    ## develop
    ".config/mise".source = ../../.config/mise;

    # # You can also set the file content immediately.
    # ".gradle/gradle.properties".text = ''
    #   org.gradle.console=verbose
    #   org.gradle.daemon.idletimeout=3600000
    # '';
  };

  fonts.fontconfig.enable = true;

  # Home Manager can also manage your environment variables through
  # 'home.sessionVariables'. These will be explicitly sourced when using a
  # shell provided by Home Manager. If you don't want to manage your shell
  # through Home Manager then you have to manually source 'hm-session-vars.sh'
  # located at either
  #
  #  ~/.nix-profile/etc/profile.d/hm-session-vars.sh
  #
  # or
  #
  #  ~/.local/state/nix/profiles/profile/etc/profile.d/hm-session-vars.sh
  #
  # or
  #
  #  /etc/profiles/per-user/nakamura-yuki/etc/profile.d/hm-session-vars.sh
  #
  # Let Home Manager install and manage itself.
  programs.home-manager.enable = true;
}
