let
  username = "@user@";
  hostname = "@home@";
in
{
  name = "${username}";
  user = "${username}";
  system = "aarch64-darwin";
  modules = [
    ../common.nix
    ../mac.nix
  ];
}
