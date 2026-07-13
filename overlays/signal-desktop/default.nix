{ channels, inputs, ... }:
final: prev: {
  inherit (channels.upstream) signal-desktop;
}
