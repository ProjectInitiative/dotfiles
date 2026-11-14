# SPDX-License-Identifier: GPL-2.0
# Surface Laptop Ultra (N1X) SSAM helpers. The module list is in Kbuild.
# Both modules are new, self-contained out-of-tree code; nothing in-tree is
# replaced.
KVER ?= $(shell uname -r)
KDIR ?= /lib/modules/$(KVER)/build

all:
	$(MAKE) -C $(KDIR) M=$(CURDIR) modules

clean:
	$(MAKE) -C $(KDIR) M=$(CURDIR) clean

.PHONY: all clean
