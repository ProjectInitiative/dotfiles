{ lib, ... }:
let
  inherit (lib) types;
in
rec {
  ## Create a bcachefs mirror configuration for Disko
  ##
  ## ```nix
  ## mkBcachefsMirror {
  ##   disks = [ "/dev/sda" "/dev/sdb" ];
  ##   encryption = true;
  ##   label = "root";
  ## }
  ## ```
  ##
  #@ { disks: [str], encryption: bool ? false, label: str ? "nixos" } -> Attrs
  mkBcachefsMirror = { disks, encryption ? false, label ? "nixos" }:
    let
      encryptedType = if encryption then "luks" else "none";
    in
    {
      disk = lib.genAttrs disks (dev: {
        type = "disk";
        device = dev;
        content = {
          type = "gpt";
          partitions = {
            boot = {
              size = "1G";
              type = "EF00";
              content = {
                type = "filesystem";
                format = "vfat";
                mountpoint = "/boot";
              };
            };
            root = {
              size = "100%";
              content = {
                type = "bcachefs";
                extraArgs = [
                  "--label=${label}"
                  "--metadata_replicas=2"
                  "--data_replicas=2"
                ];
                ${lib.optionalString encryption "encrypted"} = { inherit encryptedType; };
              };
            };
          };
        };
      });
    };
}
