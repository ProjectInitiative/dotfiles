{ channels, inputs, ... }:

final: prev: {
  inherit (channels.unstable) bitwarden-desktop;
}
