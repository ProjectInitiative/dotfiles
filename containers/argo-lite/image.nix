{
  pkgs,
  home-manager,
  authorizedKeys,
}:

let
  home = home-manager.lib.homeManagerConfiguration {
    inherit pkgs;
    modules = [ ./home.nix ];
  };

  # fakeNss ships a read-only /etc/passwd; we need our own with kylepzak's
  # entry (sshd runs as UID 1000 and calls getpwuid), so build a small etc.
  etc = pkgs.runCommand "argo-lite-etc" { } ''
        mkdir -p $out/etc
        cat > $out/etc/passwd <<'EOF'
    root:x:0:0::/root:/bin/sh
    kylepzak:x:1000:100::/home/kylepzak:${pkgs.zsh}/bin/zsh
    EOF
        cat > $out/etc/group <<'EOF'
    root:x:0:
    kylepzak:x:100:
    EOF
        cat > $out/etc/nsswitch.conf <<'EOF'
    hosts: files dns
    EOF
        chmod 0444 $out/etc/*
  '';

  sshdConfig = pkgs.writeText "argo-lite-sshd_config" ''
    Port 2222
    AddressFamily any
    ListenAddress 0.0.0.0
    HostKey /tmp/ssh_host_ed25519_key
    PidFile /tmp/sshd.pid
    PermitRootLogin no
    PasswordAuthentication no
    KbdInteractiveAuthentication no
    PubkeyAuthentication yes
    AuthorizedKeysFile /etc/ssh/authorized_keys
    UsePAM no
    AllowUsers kylepzak
    Subsystem sftp ${pkgs.openssh}/libexec/sftp-server
  '';

  entrypoint = pkgs.writeShellScript "argo-lite-entrypoint" ''
    set -eu
    mkdir -p /tmp/sshd
    chmod 700 /tmp/sshd
    if [ ! -s /tmp/ssh_host_ed25519_key ]; then
      ${pkgs.openssh}/bin/ssh-keygen -q -t ed25519 -N "" -f /tmp/ssh_host_ed25519_key
    fi
    exec ${pkgs.openssh}/bin/sshd -D -e -f ${sshdConfig}
  '';
in
pkgs.dockerTools.buildLayeredImage {
  name = "argo-lite";
  tag = "latest";

  contents = [
    home.config.home.path
    pkgs.bashInteractive
    pkgs.coreutils
    etc
    pkgs.openssh
    pkgs.zsh
  ];

  fakeRootCommands = ''
    mkdir -p ./home/kylepzak ./etc/ssh ./tmp
    chmod 1777 ./tmp
    # authorizedKeys already ends with a newline; do NOT use '%s\\n' here —
    # Nix indented strings don't process backslash escapes, so that emits a
    # literal backslash-n into the file and corrupts the next key line.
    printf '%s' '${authorizedKeys}' > ./etc/ssh/authorized_keys
    chmod 0444 ./etc/ssh/authorized_keys
    chown -R 1000:100 ./home/kylepzak
  '';

  config = {
    User = "1000:100";
    WorkingDir = "/home/kylepzak";
    Entrypoint = [ "${entrypoint}" ];
    ExposedPorts = {
      "2222/tcp" = { };
    };
    Env = [
      "HOME=/home/kylepzak"
      "USER=kylepzak"
      "LOGNAME=kylepzak"
      "SHELL=${pkgs.zsh}/bin/zsh"
      "PATH=${home.config.home.path}/bin:${pkgs.openssh}/bin:${pkgs.coreutils}/bin:${pkgs.bashInteractive}/bin:${pkgs.zsh}/bin"
      "EDITOR=hx"
      "VISUAL=hx"
    ];
  };
}
