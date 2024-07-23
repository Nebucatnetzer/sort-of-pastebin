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
            cryptography = super.cryptography.overridePythonAttrs (old: rec {
              cargoDeps = pkgs.rustPlatform.fetchCargoTarball {
                inherit (old) src;
                name = "${old.pname}-${old.version}";
                sourceRoot = "${old.pname}-${old.version}/${cargoRoot}";
                sha256 = "sha256-PgxPcFocEhnQyrsNtCN8YHiMptBmk1PUhEDQFdUR1nU=";
              };
              cargoRoot = "src/rust";
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
                  };
                  enterShell = ''
                    ln -sf ${config.process-managers.process-compose.configFile} ${config.env.DEVENV_ROOT}/process-compose.yml
                  '';
                  packages = [
                    env
                    pkgs.poetry
                  ];
                  process-managers.process-compose.enable = true;
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
