// SPDX-License-Identifier: GPL-2.0
/*
 * Diagnostic: set MT8901 SoundWire pad drive strength through the pinctrl
 * core (paris only implements per-group pinconf; each pin is a group).
 * Applies once at load; the pad keeps the setting after unload.
 */
#include <linux/module.h>
#include <linux/platform_device.h>
#include <linux/pinctrl/machine.h>
#include <linux/pinctrl/consumer.h>
#include <linux/pinctrl/pinconf-generic.h>

#define DEVNAME "sdw-pad-drive"
#define PCTL    "NVDA9221:00"

static char *groups[8] = { "GPIO66", "GPIO67" };
static int ngroups = 2;
module_param_array(groups, charp, &ngroups, 0444);
static int ma = 8;
module_param(ma, int, 0444);

static unsigned long cfg[1];
static struct pinctrl_map maps[8];

static int __init sdw_pad_drive_init(void)
{
	struct platform_device *pdev;
	struct pinctrl *p;
	struct pinctrl_state *s;
	int i, ret;

	if (ma < 2 || ma > 16 || ngroups < 1)
		return -EINVAL;
	cfg[0] = pinconf_to_config_packed(PIN_CONFIG_DRIVE_STRENGTH, ma);
	for (i = 0; i < ngroups; i++) {
		maps[i].dev_name = DEVNAME;
		maps[i].name = PINCTRL_STATE_DEFAULT;
		maps[i].type = PIN_MAP_TYPE_CONFIGS_GROUP;
		maps[i].ctrl_dev_name = PCTL;
		maps[i].data.configs.group_or_pin = groups[i];
		maps[i].data.configs.configs = cfg;
		maps[i].data.configs.num_configs = 1;
	}
	ret = pinctrl_register_mappings(maps, ngroups);
	if (ret)
		return ret;
	pdev = platform_device_register_simple(DEVNAME, -1, NULL, 0);
	if (IS_ERR(pdev)) {
		ret = PTR_ERR(pdev);
		goto out_map;
	}
	p = pinctrl_get(&pdev->dev);
	if (IS_ERR(p)) {
		ret = PTR_ERR(p);
		goto out_dev;
	}
	s = pinctrl_lookup_state(p, PINCTRL_STATE_DEFAULT);
	ret = IS_ERR(s) ? PTR_ERR(s) : pinctrl_select_state(p, s);
	pr_info("sdw_pad_drive: %d groups -> %d mA: %d\n", ngroups, ma, ret);
	pinctrl_put(p);
out_dev:
	platform_device_unregister(pdev);
out_map:
	pinctrl_unregister_mappings(maps);
	return ret;
}
static void __exit sdw_pad_drive_exit(void) { }
module_init(sdw_pad_drive_init);
module_exit(sdw_pad_drive_exit);
MODULE_LICENSE("GPL");
MODULE_DESCRIPTION("diag: SoundWire pad drive strength");
