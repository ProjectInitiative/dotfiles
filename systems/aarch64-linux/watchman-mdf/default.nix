# Watchman-MDF — NanoPi NEO3 Plus (RK3528A) in the MDF room.
#
# All common estate config lives in modules/nixos/hosts/watchman/ — this
# file is per-host bits only.
#
# Initial flash image:
#   nix build .#nixosConfigurations.watchman-mdf.config.system.build.rockchipImages
#
# TODO: the Unifi alarm bridge moves here from its current home once the
# hardware is deployed (arriving the week of 2026-10-06).
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

  networking.hostName = "watchman-mdf";

  ${namespace}.hosts.watchman = {
    enable = true;

    # The MDF UPS is USB-attached to anchor, which runs its own NUT — keep
    # NUT off here unless a second UPS gets attached to this box.
    nut.enable = lib.mkForce false;
  };
}
