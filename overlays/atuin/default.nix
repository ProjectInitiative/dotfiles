# Pin Atuin to the version carried by our nixpkgs master pin ("upstream").
#
# nixpkgs 26.05 ships atuin 18.15.2, which predates the Threads / resume /
# mcp / output-capture feature set. The "upstream" input (nixpkgs master,
# currently at 18.24.x) has them. Once 26.05 catches up this overlay can be
# deleted and `pkgs.atuin` used directly.
{ channels, ... }:
final: prev: {
  atuin = channels.upstream.atuin;
}
