# CCU firmware

(Japanese: [README_jp.md](README_jp.md))

The camera's CCU (Camera Control Unit) runs on NVIDIA's signed firmware,
`nvCCU.img`. It is NVIDIA's property, so it is **not included** in this
repository. Copy it from the Windows install that came with your own machine.
The SoC's Root of Trust only starts images signed by NVIDIA, so no other
firmware would work anyway.

## Extract

`extract-from-windows.sh` mounts the Windows partition read-only (or uses one
that is already mounted), finds the newest `nvccu.inf_arm64_*` package in the
driver store, and copies `nvCCU.img` next to the script.

```sh
sudo ./extract-from-windows.sh                  # auto-detect the Windows partition
sudo ./extract-from-windows.sh /dev/nvme0n1p3   # name the partition
./extract-from-windows.sh /mnt/win              # point at a mounted Windows root
```

## Install

```sh
sudo install -Dm644 nvCCU.img /lib/firmware/nvidia/n1x/nvCCU.img
```

`surface_ccu_boot` loads it from this path when the Root of Trust device
(ACPI `NVDA8600`) is probed.

The file is a container bundling images for several SoCs; the driver uses the
one for `mt8991`.
