# NVSDK: the SDK headers of NVIDIA's open-gpu-kernel-modules, same version as the driver
NVSDK ?= /usr/src/nvidia-$(shell cat /sys/module/nvidia/version)/src/common/sdk/nvidia/inc

nvpcf-shim.so: nvpcf-shim.c
	$(CC) -O2 -Wall -shared -fPIC -I$(NVSDK) -o $@ $< -ldl -lm -lpthread

clean:
	rm -f nvpcf-shim.so
