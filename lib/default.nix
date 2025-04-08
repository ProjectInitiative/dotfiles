# This file can be used to define custom library functions specific to your configuration.
# Nilla provides its own extensions via `nilla.lib`.
# Standard Nixpkgs functions are available via `pkgs.lib`.

{ lib, pkgs, inputs, ... }:

{
  # Add your custom library functions here, if any.
  # Example:
  # myCustomFunction = value: value + 1;

  # Note: Helpers like mkOpt, mkBoolOpt, enabled, etc., that were previously
  # defined here or inherited from snowfall-lib should be replaced with
  # standard nixpkgs lib functions (lib.mkOption, lib.mkEnableOption, etc.)
  # directly within your modules.
}
