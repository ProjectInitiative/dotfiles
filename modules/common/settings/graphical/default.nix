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
in
{
  options.${namespace} = {
    isGraphical = mkOption {
      description = "Whether this is a graphical environment";
      type = types.bool;
      readOnly = true;
      # if we are consuming this module from Home-Manager, osConfig will be present, so
      # we will attempt to pull the OS level config to check if a graphical environment is
      # present
      default =
        if (isHomeManager && isNixOS) then
          # Home-manager with NixOS config available
          osConfig.services.xserver.enable
        else if isNixOS then
          # Pure NixOS system
          config.services.xserver.enable
        else if isDarwin then
          # Darwin systems (both with/without home-manager)
          true # Darwin is always graphical
        else if isHomeManager then
          # Home-manager without OS config
          config.xsession.enable
        else
          # Linux without home-manager/NixOS
          false; # Assume non-graphical by default
    };

    # test = mkOption {
    #   type = types.bool;
    #   readOnly = true;
    #   default = if osConfig != null
    #     then osConfig.services.xserver.enable
    #     else config.xsession.enable;
    #   description = "Test option using osConfig if available";
    # };
  };

  # empty config since we are returning an readonly option
  config = { };
}
