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
}
