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
      devenv,
      flake-utils,
      ...
    }@inputs:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = inputs.nixpkgs.legacyPackages.${system};
        poetry2nix = inputs.poetry2nix.lib.mkPoetry2Nix { inherit pkgs; };
        python = pkgs.python312;
        overrides = poetry2nix.defaultPoetryOverrides.extend (
          self: super: {
            types-peewee = super.types-peewee.overridePythonAttrs (old: {
              buildInputs = (old.buildInputs or [ ]) ++ [ super.setuptools ];
            });
            types-markupsafe = super.types-markupsafe.overridePythonAttrs (old: {
              buildInputs = (old.buildInputs or [ ]) ++ [ super.setuptools ];
            });
            types-werkzeug = super.types-werkzeug.overridePythonAttrs (old: {
              buildInputs = (old.buildInputs or [ ]) ++ [ super.setuptools ];
            });
            types-jinja2 = super.types-jinja2.overridePythonAttrs (old: {
              buildInputs = (old.buildInputs or [ ]) ++ [ super.setuptools ];
            });
            types-flask = super.types-flask.overridePythonAttrs (old: {
              buildInputs = (old.buildInputs or [ ]) ++ [ super.setuptools ];
            });
          }
        );
        application = poetry2nix.mkPoetryApplication {
          projectDir = ./.;
          inherit overrides;
          inherit python;
        };
        env = poetry2nix.mkPoetryEnv {
          projectDir = ./.;
          groups = [ "dev" ];
          editablePackageSources = {
            snapbin = ./snapbin;
          };
          inherit overrides;
          inherit python;
        };
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
                    DEBUG = "True";
                    NO_SSL = "True";
                    PC_PORT_NUM = "9999";
                    PC_SOCKET_PATH = config.process.managers.process-compose.unixSocket.path;
                  };
                  packages = [
                    env
                    pkgs.poetry
                  ];
                  process.manager.implementation = "process-compose";
                  process.managers.process-compose = {
                    enable = true;
                    unixSocket.enable = true;
                  };
                  processes = {
                    webserver = {
                      exec = "gunicorn snapbin.main:app";
                    };
                  };
                }
              ];
            };
          };
      }
    );
}
