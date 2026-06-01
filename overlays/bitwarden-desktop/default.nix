{ channels, inputs, ... }:

final: prev: {
  inherit (channels.upstream) bitwarden-desktop;
}
