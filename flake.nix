{
  description = "ContainerCraft Ansible — OPNsense edge automation; konductor toolchain + vendored oxlorg.opnsense collection";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
    flake-utils.url = "github:numtide/flake-utils";
    # konductor provides the full toolchain: the ansible category ships
    # ansible-core (with httpx) plus the hermetic ansible-lint wrapper, and the
    # linters category ships yamllint. The repo's devShell inherits konductor's
    # `full` shell (see below) so all three are on PATH.
    konductor.url = "github:braincraftio/konductor";
  };

  outputs =
    {
      nixpkgs,
      flake-utils,
      konductor,
      ...
    }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = import nixpkgs { inherit system; };

        # oxlorg.opnsense collection, content-addressed at the pinned tag.
        opnsenseSrc = pkgs.fetchFromGitHub {
          owner = "O-X-L";
          repo = "ansible-opnsense";
          rev = "25.7.8";
          hash = "sha256-k9jh3ZMEP2Q5IbrenDEAYGPfut0hZjOg9QPGuCHkaIE=";
        };

        # ANSIBLE_COLLECTIONS_PATH requires ansible_collections/<ns>/<name>/.
        opnsenseCollection = pkgs.runCommand "oxlorg-opnsense-25.7.8" { } ''
          mkdir -p $out/ansible_collections/oxlorg/opnsense
          cp -r ${opnsenseSrc}/. $out/ansible_collections/oxlorg/opnsense/
        '';

        # Python with httpx for Ansible module execution.
        # toPythonApplication seals httpx inside ansible-core's wrapper process.
        # Ansible modules run as separate Python subprocesses via interpreter
        # discovery, which finds a bare Python without httpx. This derivation
        # puts a python3 with httpx on PATH so discovery finds it.
        pythonWithHttpx = pkgs.python3.withPackages (ps: [ ps.httpx ]);

        collectionsHook = ''
          # Ansible writes to ~/.ansible; ensure a writable HOME for ephemeral shells.
          if [ ! -w "$HOME" ]; then
            HOME="$(mktemp -d)"
            export HOME
          fi
          export ANSIBLE_COLLECTIONS_PATH="${opnsenseCollection}''${ANSIBLE_COLLECTIONS_PATH:+:$ANSIBLE_COLLECTIONS_PATH}"
          # Hermetic resolution: do not scan sys.path; fail on engine/collection mismatch.
          export ANSIBLE_COLLECTIONS_SCAN_SYS_PATH=false
          export ANSIBLE_COLLECTIONS_ON_ANSIBLE_VERSION_MISMATCH=error
          # Pin module interpreter to the devshell python3 (has httpx).
          # Prevents Ansible discovery from finding a bare nix-store Python.
          export ANSIBLE_PYTHON_INTERPRETER="$(command -v python3)"
        '';
      in
      {
        packages.collection = opnsenseCollection;

        # Inherit konductor's full toolchain (ansible engine + wrapped linters),
        # then layer pythonWithHttpx, the vendored collection, and hermetic env.
        devShells.default = konductor.devShells.${system}.full.overrideAttrs (old: {
          buildInputs = (old.buildInputs or [ ]) ++ [ pythonWithHttpx ];
          shellHook = (old.shellHook or "") + "\n" + collectionsHook;
        });
      }
    );
}
