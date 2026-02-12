
let
  profiles = [
    "wsl-office"
    "mac-office"
  ]
  |> map (n: import ./${n}.nix);
in
profiles
|> map (profile: {
  # homeConfigurations."${name}" = { user = ...; modules = ...; }
  inherit (profile) name;
  value = removeAttrs profile [ "name" ];
})
|> builtins.listToAttrs

