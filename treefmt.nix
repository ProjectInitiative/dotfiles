{
  projectRootFile = "flake.nix";

  programs.nixfmt.enable = true;
  programs.prettier.enable = true;

  settings.global.excludes = [ "*.enc.yaml" ];
}
