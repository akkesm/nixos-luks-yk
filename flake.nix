{
  description = "Helper tool for setting up a YubiKey encrypted LUKS disk";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

  outputs = { self, nixpkgs }:
    let
      supportedSystems = [ "x86_64-linux" "i686-linux" "aarch64-linux" ];
      forAllSystems = f: nixpkgs.lib.genAttrs supportedSystems ( system: f system );
      nixpkgsFor = forAllSystems (system: import nixpkgs {
        inherit system;
        overlays = [ self.overlay ];
      });
    in
    {
      overlay = import ./overlay.nix {
        pbkdf2-sha512-src = (nixpkgs + "/nixos/modules/system/boot/pbkdf2-sha512.c" );
      };

      packages = forAllSystems (system: {
        inherit (nixpkgsFor.${system})
          hextorb
          rbtohex
          pbkdf2-sha512
          luks-setup
          luks-unlock;
      });

      devShell = forAllSystems (system:
        import ./shell.nix { pkgs = nixpkgsFor.${system}; }
      );
    };
}
