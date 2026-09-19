{
  options,
  config,
  pkgs,
  lib,
  namespace,
  host ? "keep",
  ...
}:
with lib;
with lib.${namespace};
let
  cfg = config.${namespace}.hosts.keep;

  # k3s environment file (raised GOMEMLIMIT to match the lighthouse footprint)
  k3sEnvFile = pkgs.writeTextFile {
    name = "k3s-keep-env";
    text = builtins.readFile ./k3s-keep-env;
  };

  # Ports a k3s node needs to talk to its peers. These are only ever opened on
  # the tailnet and/or the private interconnect - never on the public interface.
  clusterFirewall = {
    allowedTCPPorts = [
      22 # ssh (tailnet only)
      53 # dns
      6443 # k3s api server
      2379 # etcd client
      2380 # etcd peer
      9153 # coredns metrics
      10250 # kubelet
      10251 # kube-scheduler
      10252 # kube-controller-manager
      9100 # node-exporter (monitoring suite)
      9633 # smartctl-exporter (monitoring suite)
      12345 # alloy (monitoring suite)
    ];
    allowedTCPPortRanges = [
      {
        from = 30000;
        to = 32767;
      } # nodeport range
    ];
    allowedUDPPorts = [
      53 # dns
      8472 # flannel vxlan
    ];
  };

  clusterInterfaces = {
    tailscale0 = clusterFirewall;
  }
  // optionalAttrs (cfg.clusterInterface != "") {
    ${cfg.clusterInterface} = clusterFirewall;
  };
in
{
  options.${namespace}.hosts.keep = with types; {
    enable = mkBoolOpt false "Whether to enable the hardened OVH k8s node configuration.";
    role = mkOpt (enum [
      "server"
      "agent"
    ]) "agent" "The role of this k3s node.";
    k8sServerAddr = mkOpt str "" "Tailscale or private address of the first server node.";
    isFirstK8sNode = mkBoolOpt false "Whether this node bootstraps the cluster.";
    k8sEnable = mkBoolOpt false "Enable k3s. Kept false until the private interconnect is confirmed.";
    networkType = mkOpt (enum [
      "standard"
      "tailscale"
      "wireguard"
      "cilium"
    ]) "standard" "Network k3s uses for cluster communication.";
    publicIngress = mkBoolOpt false "Open 80/443 on the public interface (only after hardening sign-off).";
    clusterInterface =
      mkOpt str ""
        "Private interconnect interface to allow cluster ports on (e.g. ens4).";
    nodeIp = mkOpt str "" "IP to advertise as the k3s node IP.";
    nodeIface = mkOpt str "" "Interface for flannel/k3s traffic.";
    rootDiskDevice = mkOpt str "/dev/sda" "Root disk device (matches the lighthouse layout).";
    hostName = mkOpt str host "System hostname.";

    # Secret delivery seams. Nothing is embedded in the repo; these point at
    # files populated at runtime (e.g. by an Infisical agent or by hand).
    tailscaleAuthKeyFile = mkOpt (nullOr path) null "Runtime path to a tailscale auth key.";
    k8sTokenFile = mkOpt (nullOr path) null "Runtime path to the k3s node token (joiners only).";
    userPasswordFile = mkOpt (nullOr path) null "Runtime path to the user's hashed password file.";

    sudoRequiresPassword = mkBoolOpt false "Require a password for sudo. Only useful when userPasswordFile is set.";
    lockKernelModules = mkBoolOpt false "Disable kernel module loading after boot. Test carefully against k3s before enabling.";

    # Infisical Agent wiring. Placeholders only; fill these in when ready.
    infisical = {
      enable = mkBoolOpt false "Run the Infisical Agent on this node.";
      address = mkOpt str "https://app.infisical.com" "Infisical instance URL.";
      projectId = mkOpt str "<INFISICAL_PROJECT_ID>" "Infisical project UUID (placeholder).";
      environment = mkOpt str "prod" "Infisical environment slug.";
      credentialsDir = mkOpt str "/var/lib/infisical" "Directory holding the universal-auth client-id/client-secret files.";
      manageUserPassword = mkBoolOpt false "Render the user's hashed password via Infisical. Only enable once the agent is live, or activation will fail.";
    };
  };

  config = mkIf cfg.enable {
    #####################################################
    # IDENTITY
    #####################################################
    networking.hostName = mkForce cfg.hostName;
    time.timeZone = mkForce "UTC";
    i18n.supportedLocales = [ "en_US.UTF-8/UTF-8" ];

    #####################################################
    # STRIPPED USER / NO HOME-MANAGER
    #####################################################
    home-manager.users = mkForce { };
    users.users.kylepzak = mkForce {
      isNormalUser = true;
      name = "kylepzak";
      home = "/home/kylepzak";
      group = "users";
      extraGroups = [ "wheel" ];
      shell = pkgs.bash;
      openssh.authorizedKeys.keys = mkForce [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDRiGsoimWWFcrnXlN8+AcdkZba43h1D26D5Ep3KDDYe"
      ];
      hashedPasswordFile = mkIf (cfg.userPasswordFile != null) cfg.userPasswordFile;
      hashedPassword = mkIf (cfg.userPasswordFile == null) "!";
    };

    users.users.root.hashedPassword = mkForce "!";

    # No embedded secrets means no stored password by default; sudo is then
    # gated only by the SSH key + tailnet ACLs. Turn this on once a password
    # file is delivered at runtime.
    security.sudo.wheelNeedsPassword = mkForce cfg.sudoRequiresPassword;
    security.sudo-rs.wheelNeedsPassword = mkForce cfg.sudoRequiresPassword;

    # Do not apply the global sops/encryption module to these nodes.
    enableCommonEncryption = mkForce false;

    #####################################################
    # KERNEL / OS HARDENING
    #####################################################
    security = {
      apparmor.enable = true;
      auditd.enable = true;
      protectKernelImage = true;
      lockKernelModules = cfg.lockKernelModules;
    };

    boot = {
      # OVH KVM/QEMU virtio devices
      initrd.availableKernelModules = [
        "virtio_pci"
        "virtio_blk"
        "virtio_scsi"
        "virtio_net"
        "ahci"
        "sd_mod"
        "sr_mod"
      ];
      initrd.kernelModules = [
        "virtio_pci"
        "virtio_blk"
        "virtio_net"
      ];

      kernelParams = [
        "init_on_alloc=1"
        "init_on_free=1"
        "page_alloc.shuffle=1"
        "slab_nomerge"
        "randomize_kstack_offset=on"
        "vsyscall=none"
        "oops=panic"
        "panic=10"
        "pti=on"
      ];

      # Modules k3s/CNI/proxy need available before any module lock kicks in.
      kernelModules = [
        "overlay"
        "br_netfilter"
        "vxlan"
        "ip_tables"
        "iptable_nat"
        "iptable_filter"
        "nf_conntrack"
        "wireguard"
        "ip_vs"
        "ip_vs_rr"
        "ip_vs_wrr"
        "ip_vs_sh"
      ];

      # A cloud VPS has none of this hardware.
      blacklistedKernelModules = [
        "firewire_core"
        "firewire_ohci"
        "firewire_sbp2"
        "bluetooth"
        "btusb"
        "dccp"
        "sctp"
        "rds"
        "tipc"
        "usb_storage"
        "uas"
        "vivid"
      ];

      kernel.sysctl = {
        "kernel.dmesg_restrict" = 1;
        "kernel.kptr_restrict" = 2;
        "kernel.yama.ptrace_scope" = 1;
        "kernel.unprivileged_bpf_disabled" = 1;
        "net.core.bpf_jit_harden" = 2;
        "kernel.randomize_va_space" = 2;
        "vm.mmap_min_addr" = 65536;
        "fs.protected_hardlinks" = 1;
        "fs.protected_symlinks" = 1;
        "fs.protected_fifos" = 2;
        "fs.protected_regular" = 2;
        "net.ipv4.conf.all.rp_filter" = 1;
        "net.ipv4.conf.default.rp_filter" = 1;
        "net.ipv4.tcp_syncookies" = 1;
        "net.ipv4.conf.all.accept_redirects" = 0;
        "net.ipv4.conf.default.accept_redirects" = 0;
        "net.ipv4.conf.all.send_redirects" = 0;
        "net.ipv4.conf.all.accept_source_route" = 0;
        "net.ipv6.conf.all.accept_redirects" = 0;
      };
    };

    #####################################################
    # STRIP UNUSED SERVICES / DOCS
    #####################################################
    services.udisks2.enable = mkForce false;
    services.avahi.enable = mkForce false;
    services.printing.enable = mkForce false;
    services.pcscd.enable = mkForce false;

    documentation = {
      enable = mkForce false;
      nixos.enable = mkForce false;
    };

    services.journald.extraConfig = ''
      Storage=persistent
      SystemMaxUse=500M
      MaxRetentionSec=1month
      ForwardToSyslog=no
    '';

    #####################################################
    # SSH - key only, reachable over the tailnet only
    #####################################################
    services.openssh = {
      enable = true;
      openFirewall = false;
      settings = {
        PasswordAuthentication = false;
        KbdInteractiveAuthentication = false;
        PermitRootLogin = "no";
        PermitEmptyPasswords = false;
        AuthenticationMethods = "publickey";
        AllowUsers = [ "kylepzak" ];
        MaxAuthTries = 3;
        LoginGraceTime = 20;
        ClientAliveInterval = 300;
        ClientAliveCountMax = 2;
        AllowAgentForwarding = false;
        AllowTcpForwarding = false;
        X11Forwarding = false;
        PermitTunnel = false;
        LogLevel = "VERBOSE";
        KexAlgorithms = [
          "curve25519-sha256"
          "curve25519-sha256@libssh.org"
          "diffie-hellman-group16-sha512"
          "diffie-hellman-group18-sha512"
        ];
        Ciphers = [
          "chacha20-poly1305@openssh.com"
          "aes256-gcm@openssh.com"
          "aes128-gcm@openssh.com"
        ];
        Macs = [
          "hmac-sha2-256-etm@openssh.com"
          "hmac-sha2-512-etm@openssh.com"
        ];
      };
    };

    services.fail2ban = {
      enable = true;
      maxretry = 3;
      bantime = "24h";
      bantime-increment = {
        enable = true;
        maxtime = "168h";
        overalljails = true;
      };
      jails.sshd.settings = {
        enable = true;
        mode = "aggressive";
      };
    };

    #####################################################
    # NETWORKING / FIREWALL
    #####################################################
    networking = {
      useNetworkd = true;
      networkmanager.enable = mkForce false;

      # Default deny. Public surface is empty (or 80/443 once sign-off is
      # given); every cluster port lives on the tailnet/private interconnect.
      firewall = mkForce {
        enable = true;
        allowPing = false;
        allowedTCPPorts = optionals cfg.publicIngress [
          80
          443
        ];
        allowedUDPPorts = [
          41641 # tailscale direct connection
        ];
        interfaces = clusterInterfaces;
      };
    };

    # Everything under the projectinitiative namespace for this host. It must
    # live in a single dynamic attr; Nix rejects two `${namespace}.x` paths.
    ${namespace} = {
      system.nix-config.enable = true;

      # Turn off the shared user module; this host defines its own stripped user.
      user.enable = mkForce false;

      # Infisical agent renders node secrets to /run/secrets at runtime. No
      # secret material is ever embedded in the Nix store.
      services.infisical = mkIf cfg.infisical.enable {
        enable = true;
        address = cfg.infisical.address;
        projectId = cfg.infisical.projectId;
        environment = cfg.infisical.environment;
        credentialsDir = cfg.infisical.credentialsDir;
        secrets = [
          {
            name = "TAILSCALE_AUTH_KEY";
            path = "/run/secrets/tailscale_auth_key";
          }
          {
            name = "K3S_TOKEN";
            path = "/run/secrets/k3s_token";
          }
          {
            name = "USER_PASSWORD_HASH";
            path = "/run/secrets/user_password";
          }
        ];
      };

      # Default the runtime seams to the agent's rendered paths. The user
      # password is deliberately opt-in: pointing hashedPasswordFile at a file
      # that does not exist yet can break activation on first boot.
      hosts.keep = {
        tailscaleAuthKeyFile = mkIf cfg.infisical.enable "/run/secrets/tailscale_auth_key";
        k8sTokenFile = mkIf cfg.infisical.enable "/run/secrets/k3s_token";
        userPasswordFile = mkIf (cfg.infisical.enable && cfg.infisical.manageUserPassword) "/run/secrets/user_password";
      };

      # Tailscale is for remote access / ssh only. Cluster traffic is left to
      # the private interconnect (networkType controls k3s, not this).
      networking.tailscale = {
        enable = true;
        ephemeral = false;
        useSops = false;
        authKeyFile = cfg.tailscaleAuthKeyFile;
        extraArgs = [
          "--accept-routes=true"
          "--advertise-routes="
          "--snat-subnet-routes=true"
        ];
      };

      # K3S (plumbed, disabled until the interconnect is confirmed).
      services.k8s = mkIf cfg.k8sEnable {
        enable = true;
        tokenFile = cfg.k8sTokenFile;
        isFirstNode = cfg.isFirstK8sNode;
        serverAddr = cfg.k8sServerAddr;
        role = cfg.role;
        networkType = cfg.networkType;
        nodeIp = cfg.nodeIp;
        nodeIface = cfg.nodeIface;
        environmentFile = k3sEnvFile;
        extraArgs = [
          "--tls-san=k8s.projectinitiative.io"
          "--secrets-encryption"
          "--disable=traefik"
          "--disable=local-storage"
        ];
      };
    };

    #####################################################
    # NIX
    #####################################################
    nix = {
      settings = {
        trusted-users = mkForce [
          "root"
          "@wheel"
        ];
        allowed-users = mkForce [
          "root"
          "@wheel"
        ];
        auto-optimise-store = true;
        experimental-features = [
          "nix-command"
          "flakes"
        ];
      };
      gc = {
        automatic = true;
        dates = "weekly";
        options = "--delete-older-than 30d";
      };
    };

    #####################################################
    # MINIMAL PACKAGES
    #####################################################
    environment.systemPackages = with pkgs; [
      vim
      git
      curl
      htop
      tailscale
    ];

    #####################################################
    # DISKO / BOOT (same layout as the lighthouse nodes)
    #####################################################
    disko.devices = {
      disk.rootSystemDisk = {
        type = "disk";
        device = cfg.rootDiskDevice;
        content = {
          type = "gpt";
          partitions = {
            boot = {
              size = "1M";
              type = "EF02";
            };
            ESP = {
              name = "ESP";
              type = "EF00";
              size = "512M";
              content = {
                type = "filesystem";
                format = "vfat";
                mountpoint = "/boot";
              };
            };
            lvm_pv_root = {
              name = "lvm_pv";
              size = "100%";
              content = {
                type = "lvm_pv";
                vg = "vgSystem";
              };
            };
          };
        };
      };

      lvm_vg.vgSystem = {
        type = "lvm_vg";
        lvs.lvRoot = {
          name = "root";
          size = "100%FREE";
          content = {
            type = "filesystem";
            format = "ext4";
            mountpoint = "/";
          };
        };
      };
    };

    boot.loader.grub = {
      enable = true;
      efiSupport = true;
      device = "nodev";
    };
    boot.loader.efi.canTouchEfiVariables = false;

  };
}
