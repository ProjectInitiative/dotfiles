{ lib, myLib, ... }: # Add myLib to arguments

with lib;
rec {
  ## Import common modules for both NixOS and Darwin systems
  ##
  ## ```nix
  ## commonModules = importCommonModules ../common;
  ## ```
  ##
  #@ Path -> [Module]
  importCommonModules =
    path:
    let
      files = myLib.fs.get-nix-files-recursive path; # Use myLib.fs
      moduleFiles = builtins.filter (
        f: !(lib.hasInfix "/darwin/" f) && !(lib.hasInfix "/nixos/" f)
      ) files;
    in
    map import moduleFiles;

  ## Check if a module is compatible with the current system
  ##
  ## ```nix
  ## isCompatible = checkModuleCompatibility "x86_64-linux" module;
  ## ```
  ##
  #@ String -> Module -> Bool
  checkModuleCompatibility =
    system: module:
    let
      platformPrefix =
        if lib.hasPrefix "x86_64-linux" system then
          "nixos"
        else if lib.hasPrefix "x86_64-darwin" system then
          "darwin"
        else
          null;
    in
    if platformPrefix == null then false else !(lib.hasInfix "/${platformPrefix}/" module);

  ## Import platform-specific and common modules
  ##
  ## ```nix
  ## modules = importPlatformModules {
  ##   path = ./.;
  ##   system = "x86_64-linux";
  ##   platformDir = "nixos";
  ## };
  ## ```
  ##
  #@ { path, system, platformDir } -> [Module]
  importPlatformModules =
    {
      path,
      system,
      platformDir,
    }:
    let
      platformPath = path + "/${platformDir}";
      commonPath = path + "/common";

      # Get all .nix files from platform-specific directory
      platformModules =
        if builtins.pathExists platformPath then
          map import (myLib.fs.get-nix-files-recursive platformPath) # Use myLib.fs
        else
          [ ];

      # Get compatible common modules
      commonModules = if builtins.pathExists commonPath then importCommonModules commonPath else [ ];
    in
    platformModules ++ commonModules;

  ## Import all modules from the common directory
  ##
  ## ```nix
  ## commonModules = importAllCommonModules ../modules/common;
  ## ```
  ##
  #@ Path -> [Module]
  importAllCommonModules =
    commonPath:
    let
      # Get all .nix files recursively from common directory
      allFiles = myLib.fs.get-nix-files-recursive commonPath; # Use myLib.fs

      # Filter out any backup files or temporary files
      validFiles = builtins.filter (
        f:
        !(lib.hasInfix "~" f)
        # Filter backup files
        && !(lib.hasInfix "#" f)
        # Filter temp files
        && !(lib.hasInfix ".#" f) # Filter temp files
      ) allFiles;
    in
    map import validFiles;

}
