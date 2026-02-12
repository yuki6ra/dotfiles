let
  username = "@user@";
  hostname = "@host@";
in
{
  name = "${username}@${hostname}";
  user = "${username}";
  system = "x86_64-linux";
  modules = [
    ../home/common.nix
    ../home/wsl-ubuntu.nix
  ];
}
