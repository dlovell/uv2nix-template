{
  description = "Hello world flake using uv2nix";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    pyproject-nix = {
      url = "github:pyproject-nix/pyproject.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    uv2nix = {
      url = "github:pyproject-nix/uv2nix";
      inputs.pyproject-nix.follows = "pyproject-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    pyproject-build-systems = {
      url = "github:pyproject-nix/build-system-pkgs";
      inputs = {
        pyproject-nix.follows = "pyproject-nix";
        uv2nix.follows = "uv2nix";
        nixpkgs.follows = "nixpkgs";
      };
    };

    uv2nix_hammer_overrides = {
      url = "github:TyberiusPrime/uv2nix_hammer_overrides";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      uv2nix,
      pyproject-nix,
      pyproject-build-systems,
      uv2nix_hammer_overrides,
      ...
    }:
    let
      inherit (nixpkgs) lib;
      workspace = uv2nix.lib.workspace.loadWorkspace { workspaceRoot = ./.; };
      overlay = workspace.mkPyprojectOverlay {
        sourcePreference = "wheel";
      };

      pyprojectOverrides = _final: _prev: {
      };

      pkgs = import nixpkgs {
        system = "x86_64-linux";
      };
      python = pkgs.python312;
      pythonSet =
        (pkgs.callPackage pyproject-nix.build.packages {
          inherit python;
        }).overrideScope
          (
            lib.composeManyExtensions [
              pyproject-build-systems.overlays.default
              overlay
              pyprojectOverrides
              (uv2nix_hammer_overrides.overrides pkgs)
            ]
          );
      virtualenv-all = pythonSet.mkVirtualEnv "hello-world-env" workspace.deps.all;
      virtualenv-default = pythonSet.mkVirtualEnv "hello-world-env" workspace.deps.default;
      impureShell = pkgs.mkShell {
        packages = [
          python
          pkgs.uv
        ];
        env =
          {
            # Prevent uv from managing Python downloads
            UV_PYTHON_DOWNLOADS = "never";
            # Force uv to use nixpkgs Python interpreter
            UV_PYTHON = python.interpreter;
          }
          // lib.optionalAttrs pkgs.stdenv.isLinux {
            # Python libraries often load native shared objects using dlopen(3).
            # Setting LD_LIBRARY_PATH makes the dynamic library loader aware of libraries without using RPATH for lookup.
            LD_LIBRARY_PATH = lib.makeLibraryPath pkgs.pythonManylinuxPackages.manylinux1;
          };
        shellHook = ''
          unset PYTHONPATH
        '';
      };

      uv2nixShell =
        let
          editableOverlay = workspace.mkEditablePyprojectOverlay {
            root = "$REPO_ROOT";
          };
          editablePythonSet = pythonSet.overrideScope (
            lib.composeManyExtensions [
              editableOverlay
              (final: prev: {
                hello-world = prev.hello-world.overrideAttrs (old: {
                  # It's a good idea to filter the sources going into an editable build
                  # so the editable package doesn't have to be rebuilt on every change.
                  src = lib.fileset.toSource {
                    root = old.src;
                    fileset = lib.fileset.unions [
                      (old.src + "/pyproject.toml")
                      (old.src + "/README.md")
                      (old.src + "/src/hello_world/__init__.py")
                    ];
                  };
                  nativeBuildInputs =
                    old.nativeBuildInputs
                    ++ final.resolveBuildSystem {
                      editables = [ ];
                    };
                });

              })
            ]
          );
          virtualenv = editablePythonSet.mkVirtualEnv "hello-world-dev-env" workspace.deps.all;
        in
        pkgs.mkShell {
          packages = [
            virtualenv
            pkgs.uv
          ];

          env = {
            # Don't create venv using uv
            UV_NO_SYNC = "1";

            # Force uv to use Python interpreter from venv
            UV_PYTHON = "${virtualenv}/bin/python";

            # Prevent uv from downloading managed Python's
            UV_PYTHON_DOWNLOADS = "never";
          };

          shellHook = ''
            # Undo dependency propagation by nixpkgs.
            unset PYTHONPATH

            # Get repository root using git. This is expanded at runtime by the editable `.pth` machinery.
            export REPO_ROOT=$(git rev-parse --show-toplevel)
          '';
        };
    in
    {
      packages.x86_64-linux = {
        inherit virtualenv-all virtualenv-default;
        default = virtualenv-default;
      };
      lib.x86_64-linux = {
        inherit pkgs;
      };
      apps.x86_64-linux = {
        default = {
          type = "app";
          program = "${self.packages.x86_64-linux.default}/bin/hello";
        };
      };
      devShells.x86_64-linux = {
        inherit impureShell uv2nixShell;
        default = self.devShells.x86_64-linux.uv2nixShell;
      };
      templates.x86_64-linux = {
        baseline = {
          path = ./templates/baseline;
          description = "baseline template";
        };
      };
      templates.default = self.templates.x86_64-linux.baseline;
    };
}
