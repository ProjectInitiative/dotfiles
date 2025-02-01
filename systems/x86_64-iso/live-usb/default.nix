{ lib, config, namespace, options, ... }:
with lib.${namespace};
{
  ${namespace} = {
    hosts.live-usb = {
      enable = true;
    };

  };
}
