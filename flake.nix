{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    systems.url = "github:nix-systems/default";
    devenv.url = "github:cachix/devenv";
  };

  outputs = { self, nixpkgs, devenv, systems, ... } @ inputs:
    let
      forEachSystem = nixpkgs.lib.genAttrs (import systems);
    in
    {
      packages = forEachSystem (system: {
        devenv-up = self.devShells.${system}.default.config.procfileScript;
      });
      devShells = forEachSystem
        (system:
          let
            pkgs = nixpkgs.legacyPackages.${system};
          in
          {
            default = devenv.lib.mkShell {
              inherit inputs pkgs;
              modules = [{
                env = {
                  NO_SSL = "True";
                  LD_LIBRARY_PATH = pkgs.lib.makeLibraryPath [
                    pkgs.stdenv.cc.cc
                  ];
                };
                languages.python = {
                  enable = true;
                  package = pkgs.python312;
                  poetry = {
                    activate.enable = true;
                    enable = true;
                    install.enable = true;
                  };
                };
                process.implementation = "process-compose";
                process-managers.process-compose.enable = true;
                processes = {
                  webserver = {
                    process-compose.depends_on.redis.condition = "process_started";
                    exec = "gunicorn src.main:app";
                  };
                };
                scripts.tests.exec = ''
                  pytest --cov=src tests.py
                '';
                services.redis.enable = true;
              }];
            };
          });
    };
}
