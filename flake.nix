{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    devenv.url = "github:cachix/devenv";
    poetry2nix = {
      url = "github:nix-community/poetry2nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs =
    {
      self,
      nixpkgs,
      devenv,
      flake-utils,
      poetry2nix,
    }@inputs:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        poetry2nix = inputs.poetry2nix.lib.mkPoetry2Nix { inherit pkgs; };
        application = poetry2nix.mkPoetryApplication {
          projectDir = ./.;
          python = pkgs.python312;
        };
        tests = pkgs.writeShellScriptBin "python-test" ''
          trap "process-compose down &> /dev/null" EXIT
          process-compose up --tui=false &
          pytest --cov=snapbin tests.py
        '';
      in
      {
        packages = {
          snapbin-image = pkgs.dockerTools.buildImage {
            name = "snapbin";
            tag = "latest";
            copyToRoot = pkgs.buildEnv {
              name = "image-root";
              paths = [ application.dependencyEnv ];
            };
            config = {
              Cmd = [
                "${application.dependencyEnv}/bin/gunicorn"
                "--bind=0.0.0.0"
                "snapbin.main:app"
              ];
            };
          };
        };
        devShells =
          let
            config = self.devShells.${system}.default.config;
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
                      exec = "gunicorn snapbin.main:app";
                    };
                  };
                  services.redis.enable = true;
                }
              ];
            };
          };
      }
    );
}
