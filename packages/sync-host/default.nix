{
  pkgs ? import <nixpkgs> { },
}:

let
  pythonEnv = pkgs.python3.withPackages (
    ps: with ps; [
      pytimeparse2
      requests
    ]
  );
in
pkgs.stdenv.mkDerivation {
  name = "sync-host";
  src = ./.;

  buildInputs = [
    pythonEnv
    pkgs.makeWrapper
  ];

  installPhase = ''
    mkdir -p $out/bin
    install -Dm755 sync-host.py $out/bin/sync-host
    wrapProgram $out/bin/sync-host \
      --prefix PATH : ${
        pkgs.lib.makeBinPath [
          pkgs.rclone
          pkgs.util-linux
          pkgs.systemd
          pkgs.coreutils
        ]
      }
  '';

  meta = with pkgs.lib; {
    description = "A utility for syncing rclone remotes with power management";
    longDescription = ''
      sync-host is a Python-based command-line tool to automate the synchronization
      of rclone remotes and schedule system wake-up via RTC. It supports concurrent
      sync operations, bcachefs snapshot integration, and power management features.
    '';
    homepage = "https://github.com/yourusername/sync-host"; # Replace with your actual repo URL if you have one
    license = licenses.mit; # Choose an appropriate license (e.g., licenses.gpl3Plus)
    maintainers = [ maintainers.kylepzak ]; # Replace with your GitHub username
    platforms = platforms.linux; # Linux-specific
  };
}
