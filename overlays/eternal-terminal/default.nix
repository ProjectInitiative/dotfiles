{ inputs, ... }:

final: prev:

{
  eternal-terminal = inputs.wrappers.lib.wrapPackage {
    pkgs = prev;
    package = prev.eternal-terminal.overrideAttrs (old: {
      meta = old.meta // {
        mainProgram = "et";
      };
    });
    env = {
      ET_NO_TELEMETRY = "1";
    };
  };
}
