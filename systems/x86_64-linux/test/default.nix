{
  lib,
  pkgs,
  inputs,
  namespace,
  config,
  options,
  ...
}:
with lib;
with lib.${namespace};
{
    # _module.args.modulePath = throw builtins.stack-trace;
    # imports =
    # [ # Include the results of the hardware scan.
    #   # ./hardware-configuration.nix
    # # ];
    # ] ++ builtins.attrValues (lib.create-custom-modules "${inputs.self}/modules/common");
    # inherit lib namespace;


    # projectinitiative = {
    #   suites = {
    #     development = enabled;
    #   };
    # };
    system.stateVersion = "24.05";

}
