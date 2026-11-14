# HID over SPI for the Surface Laptop Ultra (N1X) sensor hub, as one out-of-tree module.
# Sources are linux-7.3 drivers/hid/spi-hid/ (spi-hid-core.c, spi-hid-acpi.c) with N1X fixes:
#   - spi-hid-acpi: run _RST on the ACPI handle (device_reset() on the acpi_device never did)
#   - spi-hid-acpi: forward the EINT-only GpioInt (EINT 190) through an irq_sim interrupt
#   - spi-hid-core: refuse GET_REPORT for input reports (it would return the feature report)
# The Omarchy kernel leaves CONFIG_SPI_HID_ACPI unset; the core is built in here too (no
# exported symbols, own trace system) so the stock spi-hid.ko is neither needed nor shadowed.
obj-m += n1x-spi-hid.o
n1x-spi-hid-y := spi-hid-acpi.o spi-hid-core.o
CFLAGS_spi-hid-core.o := -I$(src)
KVER ?= $(shell uname -r)
KDIR ?= /lib/modules/$(KVER)/build
all:
	$(MAKE) -C $(KDIR) M=$(CURDIR) modules
clean:
	$(MAKE) -C $(KDIR) M=$(CURDIR) clean
