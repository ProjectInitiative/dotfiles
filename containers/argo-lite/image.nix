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

  # Generated dotfiles (zshrc, tool configs) from the HM activation —
  # home.path only provides binaries, the config files live in home-files.
  homeFiles = home.config.home-files;

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
    set -u
    # Seed $HOME from the baked dotfiles — only files that don't exist yet,
    # so image updates never clobber user modifications on the PVC.
    # Seeding is BEST-EFFORT: a PVC hiccup (odd ownership, dangling symlink,
    # transient mount state) must never block sshd from starting. Any seed
    # failure logs and continues; sshd below runs unconditionally.
    if [ -d /etc/argo-lite-home ]; then
      (cd /etc/argo-lite-home && ${pkgs.findutils}/bin/find . -mindepth 1 | while read -r f; do
        rel=''${f#./}
        t="$HOME/$rel"
        if [ ! -e "$t" ]; then
          mkdir -p "$(dirname "$t")" 2>/dev/null || { echo "seed: skip $rel (mkdir failed)" >&2; continue; }
          if ! cp -rL "/etc/argo-lite-home/$rel" "$t" 2>/dev/null; then
            echo "seed: skip $rel (copy failed)" >&2
            continue
          fi
          chown -R 1000:100 "$t" 2>/dev/null || true
          chmod -R u+w "$t" 2>/dev/null || true
        fi
      done)
    fi
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
    homeFiles
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
    # HM home-files merge into the image ROOT (./.zshrc, ./.config, ...);
    # relocate them into a seed dir the entrypoint copies to $HOME on boot
    # (only files the user doesn't already have).
    mkdir -p ./etc/argo-lite-home
    find . -maxdepth 1 ! -name '.' ! -name '..' ! -name 'bin' ! -name 'dev' \
      ! -name 'etc' ! -name 'home' ! -name 'lib' ! -name 'libexec' \
      ! -name 'nix' ! -name 'sbin' ! -name 'share' ! -name 'tmp' \
      ! -name 'usr' ! -name 'var' ! -name 'manifest.json' \
      ! -name 'README' -exec mv {} ./etc/argo-lite-home/ \;
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
