{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    poetry2nix = {
      url = "github:nix-community/poetry2nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    flake-parts.url = "github:hercules-ci/flake-parts";
    flake-utils.url = "github:numtide/flake-utils";
    process-compose-flake.url = "github:Platonic-Systems/process-compose-flake";
    services-flake.url = "github:juspay/services-flake";
  };

  outputs =
    {
      flake-parts,
      ...
    }@inputs:
    flake-parts.lib.mkFlake { inherit inputs; } (
      top@{ ... }:
      {
        imports = [
          inputs.process-compose-flake.flakeModule
        ];
        flake = {
          # Put your original flake attributes here.
        };
        systems = [
          # systems for which you want to build the `perSystem` attributes
          "x86_64-linux"
          # ...
        ];
        perSystem =
          {
            config,
            pkgs,
            ...
          }:
          let
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
            process-compose."dev-services" = {
              imports = [
                inputs.services-flake.processComposeModules.default
                {
                  services.redis."database" = {
                    dataDir = "$DEVENV_STATE/redis";
                    enable = true;
                  };
                  settings.processes.gunicorn = {
                    command = ''
                      cd "$DEVENV_ROOT"
                      ${application.dependencyEnv}/bin/gunicorn --bind=0.0.0.0 snapbin.main:app
                    '';
                  };
                }
              ];
            };
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
            devShells.default = pkgs.mkShell {
              shellHook = ''
                DEVENV_ROOT="$PWD"
                export DEVENV_ROOT
                DEVENV_STATE="$DEVENV_ROOT/.devenv/state"
                export DEVENV_STATE
                mkdir -p "$DEVENV_STATE"
                PATH="$DEVENV_ROOT/tooling/bin:$PATH"
                export PATH
              '';
              env = {
                DEBUG = "True";
                NO_SSL = "True";
                PC_PORT_NUM = "9999";
              };
              packages = [
                env
                pkgs.poetry
              ];
              inputsFrom = [
                config.process-compose."dev-services".services.outputs.devShell
              ];
            };
          };
      }
    );
}
