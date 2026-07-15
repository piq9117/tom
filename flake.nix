{
  description = "gleam template";

  inputs = {
    nixpkgs.url = github:NixOS/nixpkgs/nixpkgs-unstable;
    nix-gleam.url = github:arnarg/nix-gleam;
  };

  outputs = { self, nixpkgs, nix-gleam }:
    let
      forAllSystems = nixpkgs.lib.genAttrs nixpkgs.lib.systems.flakeExposed;
      nixpkgsFor = forAllSystems (system: import nixpkgs {
        inherit system;
        overlays = [ self.overlays nix-gleam.overlays.default ];

      });
    in
    {
      overlays = final: prev: {
        tom = final.buildGleamApplication {
          pname = "tom";
          version = "latest";
          src = ./.;
        };
      };

      packages = forAllSystems (system:
        let
          pkgs = nixpkgsFor.${system};
        in
        {
          default = pkgs.tom;
        });

      devShells = forAllSystems (system:
        let
          pkgs = nixpkgsFor.${system};
        in
        {
          default = pkgs.mkShell {
            buildInputs = with pkgs; [
              gleam
              beamPackages.erlang
              beamPackages.rebar3

              treefmt
              nixpkgs-fmt
            ];
            shellHook = ''
              export PS1='[$PWD]\n❄ '
            '';
          };
        });
    };
}
