{ config, lib, pkgs, ... }:

let
  envConfig = builtins.getEnv "HOME" + "/.env";
  loadedEnv = lib.mapAttrs (name: value: builtins.getEnv name) 
    (builtins.fromJSON (builtins.readFile envConfig));
in
{
  # ... other configurations ...

  home-manager.users.kylepzak = { pkgs, ... }: {
    # ... other home-manager configs ...

    home.file.".config/example-config".text = ''
      # Normal config stuff
      public_setting = value

      # Secret part
      secret_key = ${loadedEnv.MY_SECRET_KEY}

      # More normal config
      other_setting = other_value
    '';

    # ... more configurations ...
  };

  # ... rest of your system configuration ...
}
