{
  description = "Minimal tiling window manager for the river Wayland compositor";

  inputs.nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

  outputs =
    { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};

      ebro = pkgs.callPackage ./nix/package.nix { };

    in
    {
      packages.${system} = {
        inherit (pkgs) river;
        inherit ebro;
        default = ebro;
      };
    };
}
