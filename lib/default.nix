{ inputs, self, ... }:

let
  inherit (inputs.nixpkgs) lib;
  
  # From lib/fs.nix
  inherit (builtins) readDir pathExists filter attrNames hasAttr;
  inherit (lib) filterAttrs mapAttrsToList hasSuffix concatMap;

  is-directory-kind = kind: kind == "directory";
  is-file-kind = kind: kind == "regular";

  safe-read-directory = path:
    if pathExists path
    then readDir path
    else {};

  get-files-recursive = path: let
    entries = safe-read-directory path;
    # Convert attrset to list of paths for recursive processing
    paths = mapAttrsToList (name: kind: { inherit name kind; }) entries;
    recursive-files = concatMap (entry:
      let
        current-path = path + "/${entry.name}";
      in
      if is-directory-kind entry.kind
      then get-files-recursive current-path
      else [ current-path ]
    ) paths;
  in
    recursive-files;

  # Import module composition helpers from lib/module/default.nix
  moduleComposition = import ./module/default.nix {
    inherit lib;
    myLib = self.lib; # This will reference the final extended lib
  };

  # Import file helpers
  fileHelpers = import ./file/default.nix {
    inherit lib inputs;
  };

  # Define custom library helpers
  myLib = rec {
    # From lib/fs.nix
    fs = {
      ## Get all .nix files recursively from a directory
      get-nix-files-recursive = path:
        filter
          (p: hasSuffix ".nix" (builtins.toString p))
          (get-files-recursive path);
    };

    # From lib/file/default.nix
    inherit (fileHelpers) mkParseYAMLOrJSON;

    # From lib/module-helper.nix
    ## Create a NixOS module option.
    mkOpt = type: default: description:
      lib.mkOption { inherit type default description; };

    ## Create a NixOS module option without a description.
    mkOpt' = type: default: mkOpt type default null;

    ## Create a boolean NixOS module option.
    mkBoolOpt = mkOpt lib.types.bool;

    ## Create a boolean NixOS module option without a description.
    mkBoolOpt' = mkOpt' lib.types.bool;

    warnIfEmpty = name: value:
      if value == { } || value == [ ] || value == "" || value == null then
        lib.warn "Value for ${name} is empty." value
      else
        value;

    enabled = {
      enable = true;
    };

    disabled = {
      enable = false;
    };

    ## Manually import all common modules for the system
    ## This replaces Snowfall's auto-import magic.
    ## Note: This naive approach just imports everything.
    get-common-modules = root:
      let
        # Define directories to scan for modules
        # We replicate Snowfall's behavior of scanning ./modules/common
        common-modules-path = root + "/modules/common";

        # Get all .nix files recursively
        all-files = fs.get-nix-files-recursive common-modules-path;

      in
        # Filter out non-module files if necessary (e.g. tests, READMEs not caught by .nix)
        lib.map (import) all-files; # Use lib.map (import) to import each module

    # Add self.flakeDir which is often useful
    flakeDir = toString self;

    # Expose module composition helpers
    inherit (moduleComposition)
      importCommonModules
      checkModuleCompatibility
      importPlatformModules
      importAllCommonModules;
  };

in
  # Return the extended library
  lib.extend (self: super: {
    projectinitiative = myLib;
  } // myLib)
