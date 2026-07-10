{ channels, inputs, ... }:
final: prev: {
  herdr = inputs.herdr.packages.${final.system}.herdr;
}
