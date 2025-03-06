{
  options,
  config,
  pkgs,
  lib,
  namespace,
  osConfig ? null,
  ...
}:
with lib;
with lib.${namespace};
let
  isLinux = pkgs.stdenv.isLinux;
  isDarwin = pkgs.stdenv.isDarwin;
  isNixOS = options ? environment; # NixOS always has environment option
  isHomeManager = options ? home; # Home Manager always has home option

  # Helper function to determine graphical status when osConfig is not available
  determineGraphicalFallback = 
    if (isHomeManager && isNixOS) then
      config.services.xserver.enable
    else if isNixOS then
      config.services.xserver.enable
    else if isDarwin then
      true # Darwin is always graphical
    else if isHomeManager then
      config.xsession.enable
    else
      false; # Assume non-graphical by default
in
{
  options.${namespace} = {};  # Don't declare the option again
  
  config.${namespace} = {
    isGraphical = lib.mkForce (
      if (osConfig != null && osConfig ? ${namespace}.isGraphical) then
        osConfig.${namespace}.isGraphical
      else
        determineGraphicalFallback
    );
  };
}
