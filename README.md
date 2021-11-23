# YubiKey-based FDE on NixOS - Helper functions

This flake provides the necessary functions to set up a LUKS device
with YubiKey based authentication on NixOS,
plus a script to facilitate the process.

This is **not** a guide, please refer to [the wiki][1]
and [the accompanying repo][2].

[1]: https://nixos.wiki/wiki/Yubikey_based_Full_Disk_Encryption_(FDE)_on_NixOS
[2]: https://github.com/sgillespie/nixos-yubikey-luks

## In this repo

This flake provides:
* The following packages:
  - `hextorb`
  - `rbtohex`
  - `luks-setup`
  - `luks-unlock`
* An overlay with all the packages in the top level
* A devShell with all the packages plus cryptsetup, openssl,
  parted and yubikey-personalization

The default values for the scripts are the ones used in the guide.
