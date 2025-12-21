{
  description = "PostgreSQL 16 with pgvector and age extensions";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f system);
    in
    {
      packages = forAllSystems (system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          postgresql = pkgs.postgresql_16.withPackages (ps: [
            ps.pgvector
            ps.age
          ]);
        in
        {
          default = postgresql;
          dockerImage = import ./docker-image.nix { inherit pkgs postgresql; };
        }
      );
    };
}