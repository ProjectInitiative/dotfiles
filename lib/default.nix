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
  create-common-modules = common-path:
    let
      # Debug the raw files being found
      raw-files = lib.snowfall.fs.get-nix-files-recursive common-path;
      _ = builtins.trace "Raw files found: ${toString raw-files}" null;
      # Add debug output to see what files are being found
      debug-files = builtins.trace 
        "Found files: ${toString (lib.snowfall.fs.get-nix-files-recursive common-path)}"
        null;
      # Use snowfall's module creation function
      common-modules = lib.snowfall.module.create-modules {
        # src = builtins.toString common-path;
        src = common-path;
        overrides = {};
        alias = {};
      };
      # Debug the created modules
      debug-modules = builtins.trace 
        "Created modules: ${toString (builtins.attrNames common-modules)}"
        common-modules;
      # Convert modules set to list
      module-list = builtins.attrValues common-modules;
    in
    {
      nixos = module-list;
      home-manager = module-list;
      darwin = module-list;
    };
}
