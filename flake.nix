{
  description = "Home Manager configuration";

  inputs = {
    # Specify the source of Home Manager and Nixpkgs.
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    neovim = {
      url = "github:nix-community/neovim-nightly-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    { nixpkgs, home-manager, neovim, ... } @inputs :
    let
      overlays = [
        neovim.overlays.default
      ];
      specialArgsBase = {
        inherit inputs;
      };
    in
    {
      homeConfigurations =
        import ./.profile
        |> builtins.mapAttrs(_name: { user, modules, system }:
           let
              pkgs = nixpkgs.legacyPackages.${system};
            in
            home-manager.lib.homeManagerConfiguration {
            inherit pkgs;
            modules =
              modules
              ++ [
                {
                  nixpkgs.overlays = overlays;
                }
              ];
            extraSpecialArgs = specialArgsBase // {
              inherit user system;
            };
          }
        );
    };
}
