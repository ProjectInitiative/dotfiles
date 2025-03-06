{ channels, inputs, ... }:

final: prev: {
      buildGoModule = args: prev.buildGoModule (args // {
        preBuild = ''
          export GOPROXY=direct
          ${args.preBuild or ""}
        '';
      });
    }

