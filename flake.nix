{
  description = "nixでやんす";

  inputs = {
    # Specify the source of Home Manager and Nixpkgs.
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nix-darwin = {
      url = "github:LnL7/nix-darwin";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # neovim = {
    #   url = "github:nix-community/neovim-nightly-overlay";
    #   inputs.nixpkgs.follows = "nixpkgs";
    # };
  };

  outputs = {
    self,
    nixpkgs,
    home-manager,
    nix-darwin,
    # neovim,
    ... } @inputs :
    let
    #   overlays = [
    #     neovim.overlays.default
    #   ];
      specialArgsBase = {
        inherit inputs;
      };
    in
    {
      homeConfigurations =
        builtins.mapAttrs(_name: { user, modules, system }:
          let
            pkgs = nixpkgs.legacyPackages.${system};
          in
          home-manager.lib.homeManagerConfiguration {
          inherit pkgs modules;
        #   modules =
        #     modules
        #     ++ [
        #       {
        #         nixpkgs.overlays = overlays;
        #       }
        #     ];
          extraSpecialArgs = specialArgsBase // {
            inherit user system;
          };
        }
      )(import ./nix/home-manager/.profile);

      darwinConfigurations = 
      let
        system = "aarch64-darwin";
#         # darwinSystemArgs = 
#         # {
#         #   profile,
#         #   username,
#         #   system,
#         # };
#         # import ./nix/nix-darwin {
#         #   inherit
#         #     inputs
#         #     profile
#         #     username
#         #     system
#         #     ;
#         # };
      in
      {
        "mymac" = nix-darwin.lib.darwinSystem {
          system = system;
          modules = [
            ./nix/nix-darwin/configuration.nix
            home-manager.darwinModules.home-manager
          ];
          specialArgs = {
            inherit inputs;
          };
#         # asu = nix-darwin.lib.darwinSystem (darwinSystemArgs {
#         #     profile = "asu";
#         #     username = "nanami";
#         #     system = "aarch64-darwin";
#         #   });
#         };
      };
    };
  };
}
