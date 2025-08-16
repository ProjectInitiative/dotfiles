{
  lib,
  inputs,
  snowfall-inputs,
}:

rec {
  ## Override a package's metadata
  ##
  ## ```nix
  ## let
  ##  new-meta = {
  ##    description = "My new description";
  ##  };
  ## in
  ##  lib.override-meta new-meta pkgs.hello
  ## ```
  ##
  #@ Attrs -> Package -> Package
  override-meta =
    meta: package:
    package.overrideAttrs (attrs: {
      meta = (attrs.meta or { }) // meta;
    });

  ## Create and inject common modules into standard module paths
  #@ Path -> AttrSet
  create-common-modules =
    common-path:
    let
      common-modules = lib.snowfall.module.create-modules {
        src = lib.snowfall.fs.get-snowfall-file common-path;
        overrides = lib.full-flake-options.modules.common or { };
        alias = lib.alias.modules.common or { };
      };

      # Debug trace that won't break JSON serialization
      _ = builtins.trace "Created modules: ${toString (builtins.attrNames common-modules)}" null;
    in
    common-modules;
  # {
  #   nixos = common-modules;
  #   home-manager = common-modules;
  #   darwin = common-modules;
  # };

  warnIfEmpty =
    name: set:
    if builtins.length (builtins.attrNames set) == 0 then
      builtins.trace "Warning: ${name} is empty!" set
    else
      set;

  ## Impurely pre-seed an SSH host key via an activation script.
  ## Takes the path to the key and returns a NixOS module.
  #@ Path -> NixOS Module
  preseedSshKey =
    hostKey:
    { config, pkgs, ... }:
    {
      config = lib.mkIf (hostKey != "" && builtins.typeOf hostKey == "string") {
        system.activationScripts.preseed-ssh-key = ''
          # Make sure the source files actually exist before trying to install
          if [ ! -f "${hostKey}" ] || [ ! -f "${hostKey}.pub" ]; then
            echo "!!! SSH host key or its .pub file not found. Skipping pre-seeding."
            exit 0
          fi

          echo ">>> Preseeding SSH host key from ${hostKey}"
          install -D -m 600 ${hostKey} /etc/ssh/ssh_host_ed25519_key
          install -D -m 644 ${hostKey}.pub /etc/ssh/ssh_host_ed25519_key.pub
        '';
      };
    };
}
