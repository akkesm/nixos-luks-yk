{ pbkdf2-sha512-src }:

final: prev:

let
  luksykPackages = final.callPackage ./pkgs.nix { inherit pbkdf2-sha512-src; };
in
{
  inherit (luksykPackages)
    hextorb
    rbtohex
    pbkdf2-sha512
    luks-setup
    luks-unlock;
}
