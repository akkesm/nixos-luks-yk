{ pkgs ? import <nixpkgs> { } }:

pkgs.mkShell {
  packages = with pkgs; [
    hextorb
    rbtohex
    parted
    pbkdf2-sha512
    setup-luks
    unlock-luks

    cryptsetup
    openssl
    yubikey-personalization
  ];
}
