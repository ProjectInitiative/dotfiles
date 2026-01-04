{
  lib,
  inputs,
  namespace,
}:
let
  inherit (inputs) deploy-rs;
in
rec {
  ## Create deployment configuration for use with deploy-rs.
  ##
  ## ```nix
  ## mkDeploy {
  ##   inherit self;
  ##   exclude = [ "test-host" "dev-host" ]; # Hosts to exclude from deployment
  ##   overrides = {
  ##     my-host.system.sudo = "doas -u";
  ##   };
  ## }
  ## ```
  ##
  #@ { self: Flake, exclude: [String] ? [], overrides: Attrs ? {} } -> Attrs
  mkDeploy =
    {
      self,
      exclude ? [ ],
      overrides ? { },
    }:
    let
      hosts = self.nixosConfigurations or { };
      # Filter out excluded hosts
      names = builtins.filter (name: !(builtins.elem name exclude)) (builtins.attrNames hosts);
      nodes = lib.foldr (
        name: result:
        let
          host = hosts.${name};
          user = host.config.${namespace}.user.name or null;
          system = host.pkgs.stdenv.hostPlatform.system;
        in
        {
          ${name} = (overrides.${name} or { }) // {
            hostname = overrides.${name}.hostname or "${name}";
            profiles = (overrides.${name}.profiles or { }) // {
              system =
                (overrides.${name}.profiles.system or { })
                // {
                  path = deploy-rs.lib.${system}.activate.nixos host;
                }
                // lib.optionalAttrs (user != null) {
                  user = "root";
                  sshUser = user;
                  autoRollback = false;
                  rollbackSucceeded = false;
                }
                // lib.optionalAttrs (host.config.${namespace}.security.doas.enable or false) { sudo = "doas -u"; };
            };
          };
        } // result
      ) { } names;
    in
    {
      inherit nodes;
    };
}
# Add this to the node configuration
# // lib.optionalAttrs (host.config.disko ? devices) {
#   disko = {
#     enable = true;
#     devices = host.config.disko.devices;
#   };
# }
