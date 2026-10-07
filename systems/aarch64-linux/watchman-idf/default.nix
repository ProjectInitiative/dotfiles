# Watchman-IDF — NanoPi NEO3 Plus (RK3528A) in the IDF room.
#
# The IDF UPS is USB-attached to this box; NUT (reporting-only, no shutdown
# duty) comes from the shared estate module. All common estate config lives
# in modules/nixos/hosts/watchman/ — this file is per-host bits only.
#
# Initial flash image:
#   nix build .#nixosConfigurations.watchman-idf.config.system.build.rockchipImages
{
  inputs,
  lib,
  namespace,
  ...
}:
let
  armBoot =
    if builtins.getEnv "BUILD_ARM_NATIVE" == "true" then
      inputs.nixos-on-arm.bootModules
    else
      inputs.nixos-on-arm.bootModulesCross;
in
{
  imports = armBoot.nanopineo3plus;

  # SD-card/U-Boot image variants (option declared by the armBoot rockchip
  # module — lives here because it must not exist on hosts without armBoot).
  rockchip.image.buildVariants = {
    full = true;
    sdcard = true;
    ubootOnly = true;
  };

  networking.hostName = "watchman-idf";

  ${namespace}.hosts.watchman = {
    enable = true;
  };
}
