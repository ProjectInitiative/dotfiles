// SPDX-License-Identifier: GPL-2.0
/*
 * Surface Laptop Ultra (N1X): Modern Standby notifications for \_SB.SAPD.
 *
 * The firmware has two LPS0 devices (_CID PNP0D80) with the Microsoft
 * _DSM 11e00d56-ce64-47ce-837b-1f898f9aa461:
 *   \_SB.PEPD (NVDA6210)  - NVIDIA's platform extension. The kernel's
 *                           power_wrap (NV-Kernels #656) already calls it.
 *   \_SB.SAPD (MSHW0299)  - Surface-specific. Nothing calls it on Linux.
 *
 * SAPD's _DSM drives GIO0 pin 136, which no other ACPI method touches:
 * function 7 (Modern Standby entry) sets it low, 3/4/8/9 set it high. On
 * Windows it is therefore low for the whole sleep; on Linux it stays high.
 *
 * Send the same sequence Windows (and power_wrap for PEPD) sends, in the
 * device noirq phases: 3 (screen off), 7 (MS entry), 5 (LPS0 entry) on the
 * way down and 6 (LPS0 exit), 9 (screen on), 8 (MS exit), 4 (display on)
 * on the way up. Failures are logged and never block suspend.
 */
#include <linux/acpi.h>
#include <linux/module.h>
#include <linux/platform_device.h>
#include <linux/pm.h>

enum {
	LPS0_SCREEN_OFF	= 3,
	LPS0_DISPLAY_ON	= 4,
	LPS0_ENTRY	= 5,
	LPS0_EXIT	= 6,
	LPS0_MS_ENTRY	= 7,
	LPS0_MS_EXIT	= 8,
	LPS0_SCREEN_ON	= 9,
};

static const guid_t sapd_lps0_guid = GUID_INIT(0x11e00d56, 0xce64, 0x47ce,
	0x83, 0x7b, 0x1f, 0x89, 0x8f, 0x9a, 0xa4, 0x61);

static const u8 entry_seq[] = { LPS0_SCREEN_OFF, LPS0_MS_ENTRY, LPS0_ENTRY };
static const u8 exit_seq[] = { LPS0_EXIT, LPS0_SCREEN_ON, LPS0_MS_EXIT, LPS0_DISPLAY_ON };

static bool enable = true;
module_param(enable, bool, 0644);
MODULE_PARM_DESC(enable, "send the notifications on suspend/resume (default: on)");

static bool verbose = true;
module_param(verbose, bool, 0644);
MODULE_PARM_DESC(verbose, "log every notification sequence (default: on)");

struct sapd {
	struct device *dev;
	acpi_handle handle;
	u64 functions;
	bool entered;
	unsigned int entries;
	unsigned int failures;
};

static void sapd_call(struct sapd *s, unsigned int fn)
{
	union acpi_object *obj;

	if (!(s->functions & BIT_ULL(fn)))
		return;
	obj = acpi_evaluate_dsm(s->handle, &sapd_lps0_guid, 0, fn, NULL);
	if (!obj) {
		s->failures++;
		dev_warn(s->dev, "_DSM function %u failed\n", fn);
		return;
	}
	ACPI_FREE(obj);
}

static void sapd_run(struct sapd *s, const u8 *seq, size_t n)
{
	size_t i;

	for (i = 0; i < n; i++)
		sapd_call(s, seq[i]);
}

static int sapd_suspend_noirq(struct device *dev)
{
	struct sapd *s = dev_get_drvdata(dev);

	if (!enable)
		return 0;
	sapd_run(s, entry_seq, ARRAY_SIZE(entry_seq));
	s->entered = true;
	s->entries++;
	if (verbose)
		dev_info(dev, "entry notifications sent (#%u)\n", s->entries);
	return 0;
}

static int sapd_resume_noirq(struct device *dev)
{
	struct sapd *s = dev_get_drvdata(dev);

	/* Also called when a later suspend step fails: undo only what we did. */
	if (!s->entered)
		return 0;
	sapd_run(s, exit_seq, ARRAY_SIZE(exit_seq));
	s->entered = false;
	if (verbose)
		dev_info(dev, "exit notifications sent\n");
	return 0;
}

static const struct dev_pm_ops sapd_pm_ops = {
	NOIRQ_SYSTEM_SLEEP_PM_OPS(sapd_suspend_noirq, sapd_resume_noirq)
};

static ssize_t stats_show(struct device *dev, struct device_attribute *attr, char *buf)
{
	struct sapd *s = dev_get_drvdata(dev);

	return sysfs_emit(buf, "functions=%#llx entries=%u failures=%u enable=%d\n",
			  s->functions, s->entries, s->failures, enable);
}
static DEVICE_ATTR_RO(stats);

static int sapd_probe(struct platform_device *pdev)
{
	struct device *dev = &pdev->dev;
	acpi_handle handle = ACPI_HANDLE(dev);
	struct sapd *s;
	unsigned int fn;

	if (!handle)
		return -ENODEV;
	if (!acpi_check_dsm(handle, &sapd_lps0_guid, 0, BIT_ULL(LPS0_MS_ENTRY) | BIT_ULL(LPS0_MS_EXIT))) {
		dev_info(dev, "no Modern Standby entry/exit in _DSM, not binding\n");
		return -ENODEV;
	}

	s = devm_kzalloc(dev, sizeof(*s), GFP_KERNEL);
	if (!s)
		return -ENOMEM;
	s->dev = dev;
	s->handle = handle;
	for (fn = LPS0_SCREEN_OFF; fn <= LPS0_SCREEN_ON; fn++)
		if (acpi_check_dsm(handle, &sapd_lps0_guid, 0, BIT_ULL(fn)))
			s->functions |= BIT_ULL(fn);
	platform_set_drvdata(pdev, s);

	dev_info(dev, "Surface LPS0 notifications enabled (functions %#llx)\n", s->functions);
	return device_create_file(dev, &dev_attr_stats);
}

static void sapd_remove(struct platform_device *pdev)
{
	struct sapd *s = platform_get_drvdata(pdev);

	device_remove_file(&pdev->dev, &dev_attr_stats);
	/* Leave the pin in its awake state, as the _INI method does. */
	if (s->entered)
		sapd_run(s, exit_seq, ARRAY_SIZE(exit_seq));
}

static const struct acpi_device_id sapd_acpi_ids[] = {
	{ "MSHW0299" },
	{ }
};
MODULE_DEVICE_TABLE(acpi, sapd_acpi_ids);

static struct platform_driver sapd_driver = {
	.probe = sapd_probe,
	.remove = sapd_remove,
	.driver = {
		.name = "n1x-sapd-lps0",
		.acpi_match_table = sapd_acpi_ids,
		.pm = pm_sleep_ptr(&sapd_pm_ops),
	},
};
module_platform_driver(sapd_driver);

MODULE_DESCRIPTION("Surface Laptop Ultra (N1X) Modern Standby notifications for MSHW0299");
MODULE_LICENSE("GPL");
