{ channels, inputs, ... }:
final: prev: {
  herdr = inputs.herdr.packages.${final.stdenv.hostPlatform.system}.herdr;
}
