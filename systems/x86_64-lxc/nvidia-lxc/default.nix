{
  lib,
  pkgs,
  inputs,
  namespace,
  config,
  options,
  modulesPath,
  ...
}:
with lib;
with lib.${namespace};
{
  projectinitiative = {
    system = {
      # base-container = enabled;
    };
  };

  virtualisation = {
    podman = {
      enable = true;
      dockerCompat = false;
      defaultNetwork.settings.dns_enabled = true;
    };

    docker = {
      enable = true;
      rootless = {
        enable = true;
        setSocketVariable = true;
        daemon.settings = {
          default-runtime = "nvidia";
          runtimes.nvidia.path = "${pkgs.nvidia-container-toolkit}/bin/nvidia-container-runtime";
        };
      };
    };
  };
  users.extraGroups.docker.members = [ "kylepzak" ];
  # virtualisation.containers.cdi.dynamic.nvidia.enable = true;
  hardware.nvidia-container-toolkit.enable = true;
  boot.kernelModules = [
    "nvidia"
    "nvidia_uvm"
  ];

  nixpkgs.config.allowUnfreePredicate =
    pkg:
    builtins.elem (lib.getName pkg) [
      # Add additional package names here
      "nvidia"
      "nvidia-x11"
      "nvidia-settings"
    ];

  environment.systemPackages = with pkgs; [
    # nvidia
    # nvidia-x11
    # nvidia-settings
    linuxPackages.nvidia_x11
    cudatoolkit
    nvidia-container-toolkit
  ];

  services.xserver.enable = true;
  services.xserver.videoDrivers = [ "nvidia" ];

  hardware.nvidia = {
    modesetting.enable = true;
    powerManagement.enable = false;
    powerManagement.finegrained = false;

    open = false;

    nvidiaSettings = true;
    package = config.boot.kernelPackages.nvidiaPackages.stable;
  };

  # Optionally, if you need CUDA support
  environment.variables.CUDA_PATH = "${pkgs.cudatoolkit}";
  # Add NVIDIA libraries to system libraries path
  environment.variables = {
    LD_LIBRARY_PATH = "${pkgs.linuxPackages.nvidia_x11}/lib";
  };

}
