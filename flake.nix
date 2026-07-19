{
  description = "Denuvo bypass for Linux — NixOS module with auto-detection, UMIP disabling, and CPUID fault emulation";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs =
    { self, nixpkgs, ... }:
    let
      supportedSystems = [ "x86_64-linux" ];

      forAllSystems =
        f:
        nixpkgs.lib.genAttrs supportedSystems (
          system:
          f {
            inherit system;
            pkgs = import nixpkgs { inherit system; };
          }
        );
    in
    {
      # ──────────────────────────────────────────────────────────
      # NixOS Module
      # ──────────────────────────────────────────────────────────
      nixosModules = {
        denuvo-bypass = ./modules/denuvo-hvb.nix;
        default = self.nixosModules.denuvo-bypass;
      };

      # ──────────────────────────────────────────────────────────
      # Standalone package (for manual build/testing)
      # ──────────────────────────────────────────────────────────
      packages = forAllSystems (
        { pkgs, system }: {
          denuvo-hvb = pkgs.callPackage ./pkgs/denuvo-hvb {
            kernel = pkgs.linuxPackages.kernel;
          };
          default = self.packages.${system}.denuvo-hvb;
        }
      );
    };
}
