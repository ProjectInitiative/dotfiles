# save as sd-image.nix somewhere
{ ssh-pub-keys, ... }:
{ config, pkgs, modulesPath, lib, ... }: 
{ ... }: {
  # only needed for crosscompilation
  nixpkgs.crossSystem = lib.systems.elaborate lib.systems.examples.aarch64-multiplatform;

  imports = [
    <nixpkgs/nixos/modules/installer/sd-card/sd-image-aarch64.nix>
  ];

  nixpkgs.config.allowUnfree = true; # needed for ubootRock64
  # at the time of writing the u-boot version from FireFly hasn't been successfully ported yet
  # so we use the one from Rock64
  sdImage.postBuildCommands = with pkgs; ''
    dd if=${ubootRock64}/idbloader.img of=$img conv=fsync,notrunc bs=512 seek=64
    dd if=${ubootRock64}/u-boot.itb of=$img conv=fsync,notrunc bs=512 seek=16384
  '';

  # Enable SSH
  services.openssh = {
   enable = true;
   # require public key authentication
   settings.PasswordAuthentication = false;
   settings.KbdInteractiveAuthentication = false;
   settings.PermitRootLogin = "no";
   # settings.authorizedKeysFiles = [ ssh-pub-keys ];
  };
   

  # Set your time zone.
  time.timeZone = "America/Chicago";

  users.users.kpzak = {
    isNormalUser = true;
    home = "/home/kpzak";
    # initialPassword = "initchangeme";
    description = "default admin user";
    extraGroups = [ "wheel"];
    openssh.authorizedKeys.keyFiles = [
     "${ssh-pub-keys}"
    ];
  };

  security.sudo.extraRules = [
    {
      groups = [ "wheel" ];
      commands = [ { command = "ALL"; options = [ "NOPASSWD" ]; } ];
    }
  ];
}
