{ pkgs ? import <nixpkgs> { } }:

pkgs.mkShell {
  packages = with pkgs; [
    hextorb
    rbtohex
    pbkdf2-sha512
    luks-setup
    luks-unlock

    cryptsetup
    openssl
    parted
    yubikey-personalization
  ];
}
