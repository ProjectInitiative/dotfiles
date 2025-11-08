{
  pkgs ? import <nixpkgs> { }
}:

pkgs.mkShell {
  buildInputs = with pkgs; [
    python3
    rclone
    util-linux
    systemd
    coreutils
    python3Packages.pytimeparse2
    python3Packages.requests
  ];
}
