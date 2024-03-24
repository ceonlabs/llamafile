{
  description = "devenv.sh - Fast, Declarative, Reproducible, and Composable Developer Environments";

  nixConfig = {
    extra-trusted-public-keys = "ceon.nyc:VEShUvnMY5fLrNFdg2j5d7JmOeBRM+jZilQ/PpXhQj8=";
    extra-substituters = "https://ceon.nyc";
  };

  inputs.nixpkgs.url = "github:cachix/devenv-nixpkgs/rolling";
  inputs.pre-commit-hooks = {
    url = "github:cachix/pre-commit-hooks.nix";
    inputs = {
      nixpkgs.follows = "nixpkgs";
      flake-compat.follows = "flake-compat";
    };
  };
  inputs.flake-compat = {
    url = "github:edolstra/flake-compat";
    flake = false;
  };
  inputs.nix = {
    url = "github:domenkozar/nix/devenv-2.21";
    inputs.nixpkgs.follows = "nixpkgs";
  };
  inputs.cachix = {
    url = "github:cachix/cachix";
    inputs.nixpkgs.follows = "nixpkgs";
  };


  outputs = { self, nixpkgs, pre-commit-hooks, nix, ... }@inputs:
    let
      systems = [ "x86_64-linux" "i686-linux" "x86_64-darwin" "aarch64-linux" "aarch64-darwin" ];
      forAllSystems = f: builtins.listToAttrs (map (name: { inherit name; value = f name; }) systems);
      mkPackage = pkgs: import ./package.nix { inherit pkgs inputs; };
      mkDevShellPackage = config: pkgs: import ./src/devenv-devShell.nix { inherit config pkgs; };
      mkDocOptions = pkgs:
        let
          inherit (pkgs) lib;
          eval = pkgs.lib.evalModules {
            modules = [
              ./src/modules/top-level.nix
              { devenv.warnOnNewVersion = false; }
            ];
            specialArgs = { inherit pre-commit-hooks pkgs inputs; };
          };
          sources = [
            { name = "${self}"; url = "https://github.com/cachix/devenv/blob/main"; }
            { name = "${pre-commit-hooks}"; url = "https://github.com/cachix/pre-commit-hooks.nix/blob/master"; }
          ];
          rewriteSource = decl:
            let
              prefix = lib.strings.concatStringsSep "/" (lib.lists.take 4 (lib.strings.splitString "/" decl));
              source = lib.lists.findFirst (src: src.name == prefix) { } sources;
              path = lib.strings.removePrefix prefix decl;
              url = "${source.url}${path}";
            in
            { name = url; url = url; };
          options = pkgs.nixosOptionsDoc {
            options = builtins.removeAttrs eval.options [ "_module" ];

            warningsAreErrors = false;

            transformOptions = opt: (
              opt // { declarations = map rewriteSource opt.declarations; }
            );
          };
        in
        options.optionsCommonMark;
    in
    {
      packages = forAllSystems (system:
        let pkgs = nixpkgs.legacyPackages.${system};
        in {
          default = self.packages.${system}.devenv;

          devenv = mkPackage pkgs;
          devenv-docs-options = mkDocOptions pkgs;
        });

      modules = ./src/modules;
      hasTmpDir = true;

      templates =
        let

          flake-parts = {
            path = ./templates/flake-parts;
            description = "A flake with flake-parts, direnv and devenv.";
            welcomeText = ''
	      # You are ready to run a model locally! For example:
	      ```sh
	        curl -L -o mistral.gguf https://huggingface.co/TheBloke/Mistral-7B-Instruct-v0.1-GGUF/resolve/main/mistral-7b-instruct-v0.1.Q4_K_M.gguf
	        nix run -m mistral.gguf -ngl 9999```
	      ```
	    '';
          };

          simple = {
            path = ./templates/simple;
            description = "A direnv supported Nix flake with devenv integration.";
            welcomeText = ''
	      # You are ready to run a model locally! For example:
	      ```sh
	        curl -L -o mistral.gguf https://huggingface.co/TheBloke/Mistral-7B-Instruct-v0.1-GGUF/resolve/main/mistral-7b-instruct-v0.1.Q4_K_M.gguf
	        nix run -m mistral.gguf -ngl 9999```
	      ```
	    '';
          
          };
        in
        {
          inherit simple flake-parts;
          terraform = {
            path = ./templates/terraform;
            description = "A Terraform Nix flake with devenv integration.";
            welcomeText = ''
            '';
          };
          default = simple;
        };

      flakeModule = import ./flake-module.nix self;

      lib = {
        mkConfig = args@{ pkgs, inputs, modules }:
          (self.lib.mkEval args).config;
        mkEval = { pkgs, inputs, modules }:
          let
            moduleInputs = { inherit pre-commit-hooks; } // inputs;
            project = inputs.nixpkgs.lib.evalModules {
              specialArgs = moduleInputs // {
                inherit pkgs;
                inputs = moduleInputs;
              };
              modules = [
                (self.modules + /top-level.nix)
                ({ config, ... }: {
                  packages = [
                    (mkDevShellPackage config pkgs)
                  ];
                  devenv.warnOnNewVersion = false;
                  devenv.flakesIntegration = true;
                })
              ] ++ modules;
            };
          in
          project;
        mkShell = args:
          let
            config = self.lib.mkConfig args;
          in
          config.shell // {
            ci = config.ciDerivation;
            inherit config;
          };
      };

      overlays.default = final: prev: {
        devenv = self.packages.${prev.system}.default;
      };
    };
}
