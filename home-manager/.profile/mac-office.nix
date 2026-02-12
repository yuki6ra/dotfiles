let
  username = "@user@";
  hostname = "@host@";
in
{
  name = "${username}@${hostname}";
  user = "${username}";
  system = "aarch64-darwin";
  modules = [
    ../home/common.nix
    ../home/mac.nix
  ];
}
