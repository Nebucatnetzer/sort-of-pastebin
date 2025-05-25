{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
    process-compose-flake.url = "github:Platonic-Systems/process-compose-flake";
    services-flake.url = "github:juspay/services-flake";
  };

  outputs =
    {
      self,
      flake-parts,
      ...
    }@inputs:
    flake-parts.lib.mkFlake { inherit inputs self; } (
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
            pyproject = pkgs.lib.importTOML ./pyproject.toml;
            myPython = pkgs.python312.override {
              self = myPython;
              packageOverrides = pyfinal: pyprev: {
                # An editable package with a script that loads our mutable location
                snapbin-editable = pyfinal.mkPythonEditablePackage {
                  # Inherit project metadata from pyproject.toml
                  pname = pyproject.project.name;
                  inherit (pyproject.project) version;

                  # The editable root passed as a string
                  root = "$DEVENV_ROOT/snapbin"; # Use environment variable expansion at runtime
                };
                types-peewee =
                  let
                    pname = "types-peewee";
                    version = "3.18.1.20250516";
                  in
                  pyfinal.buildPythonPackage {
                    inherit pname version;
                    format = "setuptools";
                    src = pkgs.fetchurl {
                      url = "https://files.pythonhosted.org/packages/9c/21/65fd9a10a988cc93afe5de22c0c7cffa2e20e9b31a3b964f78769f7d90c9/types_peewee-3.18.1.20250516.tar.gz";
                      hash = "sha256-wUMNUM9oZnUZhLrUYVSOXBYUNYJ9sSB2pXp5qrFyzC8=";
                    };

                    # Module doesn't have tests
                    doCheck = false;
                    pythonImportsCheck = [ "peewee-stubs" ];
                  };
              };
            };

            pythonDev = myPython.withPackages (p: [
              p.black
              p.cryptography
              p.flask
              p.freezegun
              p.gunicorn
              p.isort
              p.mypy
              p.peewee
              p.pylint
              p.pylsp-mypy
              p.pytest
              p.pytest-cov
              p.pytest-xdist
              p.python-lsp-ruff
              p.python-lsp-server
              p.ruff
              p.snapbin-editable
              p.types-peewee
            ]);
            pythonProd = pkgs.python312.withPackages (p: [
              p.cryptography
              p.flask
              p.gunicorn
              p.peewee
            ]);
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
                      ${pythonDev}/bin/gunicorn --bind=0.0.0.0 snapbin.main:app
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
                  paths = [
                    pythonProd
                    self
                  ];
                };
                config = {
                  Cmd = [
                    "${pythonProd}/bin/gunicorn"
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
                pythonDev
                pkgs.poetry
                pkgs.skopeo
              ];
              inputsFrom = [
                config.process-compose."dev-services".services.outputs.devShell
              ];
            };
          };
      }
    );
}
