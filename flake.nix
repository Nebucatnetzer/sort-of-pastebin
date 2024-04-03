{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    devenv.url = "github:cachix/devenv";
    poetry2nix = {
      url = "github:nix-community/poetry2nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      devenv,
      poetry2nix,
    }@inputs:
    let
      systems = [
        "aarch64-darwin"
        "aarch64-linux"
        "x86_64-darwin"
        "x86_64-linux"
      ];
      forEachSystem = nixpkgs.lib.genAttrs systems;
    in
    {
      packages = forEachSystem (system: {
        devenv-up = self.devShells.${system}.default.config.procfileScript;
      });
      devShells = forEachSystem (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          config = self.devShells.${system}.default.config;
          env = mkPoetryEnv {
            projectDir = ./.;
            python = pkgs.python312;
          };
          inherit (poetry2nix.lib.mkPoetry2Nix { inherit pkgs; }) mkPoetryEnv;
          tests = pkgs.writeShellScriptBin "python-test" ''
            trap "process-compose down &> /dev/null" EXIT
            process-compose up --tui=false &
            pytest --cov=src tests.py
          '';
        in
        {
          default = devenv.lib.mkShell {
            inherit inputs pkgs;
            modules = [
              {
                env = {
                  NO_SSL = "True";
                  PC_PORT_NUM = "9999";
                };
                enterShell = ''
                  ln -sf ${config.process-managers.process-compose.configFile} ${config.env.DEVENV_ROOT}/process-compose.yml
                '';
                packages = [
                  env
                  tests
                ];
                process-managers.process-compose.enable = true;
                processes = {
                  webserver = {
                    process-compose.depends_on.redis.condition = "process_started";
                    exec = "gunicorn src.main:app";
                  };
                };
                services.redis.enable = true;
              }
            ];
          };
        }
      );
    };
}
