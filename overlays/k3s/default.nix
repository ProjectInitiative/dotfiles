{ channels, inputs, ... }:
final: prev: {
  inherit (channels.k3s-pinned) k3s;
}
