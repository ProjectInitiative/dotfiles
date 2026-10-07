# AUTO-GLOBAL (snowfall imports every default.nix under modules/nixos/).
# Deliberately inert: this host family's reusable module is `host.nix`,
# imported explicitly by each PiKVM host so that options which only exist
# with hatch01/nixos-pikvm (services.kvmd, nixos-hardware raspberry-pi) are
# never referenced on hosts that don't have them.
#
# Per-host usage:
#   imports = [
#     inputs.pikvm-flake.nixosModules.default
#     ../../../modules/nixos/hosts/pikvm/host.nix
#   ];
#   projectinitiative.hosts.pikvm = {
#     enable = true;
#     bliSwitch8Port.enable = true;  # only the BliSwitch v2 8-port box
#   };
{ ... }:
{ }
