{
  options,
  config,
  lib,
  pkgs,
  namespace,
  ...
}:
with lib;
with lib.${namespace};
let
  cfg = config.${namespace}.tools.aider;
in
{
  options.${namespace}.tools.aider = with types; {
    enable = mkBoolOpt false "Whether or not to enable aider.";
  };

  config = mkIf cfg.enable {

    home = {
      packages = with pkgs; [
        #  (aider-chat.overrideAttrs (oldAttrs: {
        #   # Add dependencies to the package's runtime environment
        #   propagatedBuildInputs = (oldAttrs.propagatedBuildInputs or []) ++ [
        #     # Use the package set corresponding to the Python version
        #     # aider-chat uses by default (likely python3Packages,
        #     # but let's use python311Packages since you specified it).
        #     python312Packages.google-generativeai
        #     # google-generativeai usually pulls in 'google' itself,
        #     # but explicitly adding it doesn't hurt if needed.
        #     python312Packages.google
        #   ];

        #   # Optional: If aider-chat *must* be built/run with python311
        #   # specifically, and the default python used by nixpkgs is different,
        #   # you might need this too. Usually not required if python311 is the default
        #   # or if aider-chat doesn't strictly pin the version internally.
        #   # python = pkgs.python311;
        # }))
        aider-chat
      ];
    };
  };
}
