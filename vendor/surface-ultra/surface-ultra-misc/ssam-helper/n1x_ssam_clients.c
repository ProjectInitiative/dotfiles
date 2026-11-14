// SPDX-License-Identifier: GPL-2.0
/*
 * Surface Laptop Ultra (NVIDIA N1X): SSAM client devices for platform MSHW0733.
 *
 * The stock surface_aggregator_registry has no node group for MSHW0733, so
 * nothing registers the SAM client devices on this model. This is a minimal
 * platform hub for exactly that ACPI ID: it registers the clients below with
 * the stock SSAM bus, and the stock client drivers (surface_battery,
 * surface_charger, ...) bind to them.
 *
 * Default: battery, AC, the 11 thermal sensors (surface_temp) and fan speed
 * (surface_fan). The EC's HID devices are deliberately left out so they cannot
 * fight the I2C keyboard/touchpad. profile=1 also adds the platform profile
 * device (experimental: this EC reports profile 0, which the stock driver
 * does not know).
 *
 * If the stock registry ever gains MSHW0733, both drivers will match the same
 * platform device; whichever binds first wins and the other stays idle.
 *
 * The approach (stock SSAM plus a UART clock helper and an MSHW0733 client
 * module) is the one teo-casares described in
 * https://github.com/omacom/omarchy/discussions/15885; the UART clock and the
 * client list come from their Gist
 * https://gist.github.com/teo-casares/8b64949638e1952602a7f435bb34d5b8 and
 * linux-surface. This is an independent implementation of it.
 */

#include <linux/acpi.h>
#include <linux/module.h>
#include <linux/platform_device.h>
#include <linux/property.h>

#include <linux/surface_aggregator/device.h>

static bool profile;
module_param(profile, bool, 0444);
MODULE_PARM_DESC(profile, "Also register the platform profile device (experimental: this EC reports profile 0)");

static const struct software_node n1x_node_root = {
	.name = "n1x_ssam_platform_hub",
};

/* AC adapter. */
static const struct software_node n1x_node_bat_ac = {
	.name = "ssam:01:02:01:01:01",
	.parent = &n1x_node_root,
};

/* Primary battery. */
static const struct software_node n1x_node_bat_main = {
	.name = "ssam:01:02:01:01:00",
	.parent = &n1x_node_root,
};

/* Platform profile / performance mode, with fan profile switching. */
static const struct property_entry n1x_node_tmp_perf_profile_props[] = {
	PROPERTY_ENTRY_BOOL("has_fan"),
	{ }
};

static const struct software_node n1x_node_tmp_perf_profile = {
	.name = "ssam:01:03:01:00:01",
	.parent = &n1x_node_root,
	.properties = n1x_node_tmp_perf_profile_props,
};

/* Thermal sensors. */
static const struct software_node n1x_node_tmp_sensors = {
	.name = "ssam:01:03:01:00:02",
	.parent = &n1x_node_root,
};

/* Fan speed. */
static const struct software_node n1x_node_fan_speed = {
	.name = "ssam:01:05:01:01:01",
	.parent = &n1x_node_root,
};

/* Verified on this EC (2026-11-01): TMP sensor bitmap 0x0fbf, names, fan rpm. */
static const struct software_node *n1x_node_group_default[] = {
	&n1x_node_root,
	&n1x_node_bat_ac,
	&n1x_node_bat_main,
	&n1x_node_tmp_sensors,
	&n1x_node_fan_speed,
	NULL,
};

static const struct software_node *n1x_node_group_profile[] = {
	&n1x_node_root,
	&n1x_node_bat_ac,
	&n1x_node_bat_main,
	&n1x_node_tmp_sensors,
	&n1x_node_fan_speed,
	&n1x_node_tmp_perf_profile,
	NULL,
};

static int n1x_ssam_hub_probe(struct platform_device *pdev)
{
	const struct software_node **nodes;
	struct ssam_controller *ctrl;
	struct fwnode_handle *root;
	int status;

	nodes = profile ? n1x_node_group_profile : n1x_node_group_default;

	/*
	 * The client devices are children of this platform device, not of the
	 * controller. The device link created here makes sure they are removed
	 * before the controller and orders suspend/resume correctly.
	 */
	ctrl = ssam_client_bind(&pdev->dev);
	if (IS_ERR(ctrl))
		return PTR_ERR(ctrl) == -ENODEV ? -EPROBE_DEFER : PTR_ERR(ctrl);

	status = software_node_register_node_group(nodes);
	if (status)
		return status;

	root = software_node_fwnode(&n1x_node_root);
	if (!root) {
		status = -ENOENT;
		goto err_nodes;
	}

	set_secondary_fwnode(&pdev->dev, root);

	status = __ssam_register_clients(&pdev->dev, ctrl, root);
	if (status)
		goto err_fwnode;

	platform_set_drvdata(pdev, nodes);
	dev_info(&pdev->dev, "registered SSAM clients (%s)\n",
		 profile ? "battery, AC, sensors, fan, profile" : "battery, AC, sensors, fan");
	return 0;

err_fwnode:
	set_secondary_fwnode(&pdev->dev, NULL);
err_nodes:
	software_node_unregister_node_group(nodes);
	return status;
}

static void n1x_ssam_hub_remove(struct platform_device *pdev)
{
	const struct software_node **nodes = platform_get_drvdata(pdev);

	ssam_remove_clients(&pdev->dev);
	set_secondary_fwnode(&pdev->dev, NULL);
	software_node_unregister_node_group(nodes);
}

static const struct acpi_device_id n1x_ssam_hub_acpi_match[] = {
	/* Surface Laptop Ultra (NVIDIA N1X) */
	{ "MSHW0733" },
	{ },
};
MODULE_DEVICE_TABLE(acpi, n1x_ssam_hub_acpi_match);

static struct platform_driver n1x_ssam_hub_driver = {
	.probe = n1x_ssam_hub_probe,
	.remove = n1x_ssam_hub_remove,
	.driver = {
		.name = "n1x_ssam_platform_hub",
		.acpi_match_table = n1x_ssam_hub_acpi_match,
		.probe_type = PROBE_PREFER_ASYNCHRONOUS,
	},
};
module_platform_driver(n1x_ssam_hub_driver);

/* The SAM link only comes up once the UART clock has been fixed. */
MODULE_SOFTDEP("pre: n1x_ssam_uartclk");
MODULE_DESCRIPTION("Surface Laptop Ultra (N1X): SSAM client devices for MSHW0733");
MODULE_LICENSE("GPL");
