// SPDX-License-Identifier: GPL-2.0-only
/*
 * HID over SPI protocol, ACPI related code
 *
 * Copyright (c) 2021 Microsoft Corporation
 * Copyright (c) 2026 Google LLC
 *
 * Modified 2026 by Hiroyuki Ikegami for the Surface Laptop Ultra (NVIDIA N1X)
 * sensor hub, built out of tree as n1x-spi-hid:
 *   - run _RST on the ACPI handle (device_reset() on the acpi_device never ran it)
 *   - forward the EINT-only GpioInt (EINT 190) through an irq_sim interrupt
 *
 * This code was forked out of the HID over SPI core code, which is partially
 * based on "HID over I2C protocol implementation:
 *
 * Copyright (c) 2012 Benjamin Tissoires <benjamin.tissoires@gmail.com>
 * Copyright (c) 2012 Ecole Nationale de l'Aviation Civile, France
 * Copyright (c) 2012 Red Hat, Inc
 *
 * which in turn is partially based on "USB HID support for Linux":
 *
 * Copyright (c) 1999 Andreas Gal
 * Copyright (c) 2000-2005 Vojtech Pavlik <vojtech@suse.cz>
 * Copyright (c) 2005 Michael Haboustak <mike-@cinci.rr.com> for Concept2, Inc
 * Copyright (c) 2007-2008 Oliver Neukum
 * Copyright (c) 2006-2010 Jiri Kosina
 */

#include <linux/acpi.h>
#include <linux/delay.h>
#include <linux/device.h>
#include <linux/interrupt.h>
#include <linux/irq.h>
#include <linux/irqdomain.h>
#include <linux/irq_sim.h>
#include <linux/kernel.h>
#include <linux/module.h>
#include <linux/reset.h>
#include <linux/spinlock.h>
#include <linux/uuid.h>

#include "spi-hid.h"

/* Config structure is filled with data from ACPI */
struct spi_hid_acpi_config {
	struct spihid_ops ops;

	struct spi_hid_conf property_conf;
	u32 post_power_on_delay_ms;
	u32 minimal_reset_delay_ms;
	struct acpi_device *adev;
};

/* HID SPI Device: 6e2ac436-0fcf41af-a265-b32a220dcfab */
static guid_t spi_hid_guid =
	GUID_INIT(0x6E2AC436, 0x0FCF, 0x41AF,
		  0xA2, 0x65, 0xB3, 0x2A, 0x22, 0x0D, 0xCF, 0xAB);

static int spi_hid_acpi_populate_config(struct spi_hid_acpi_config *conf,
					struct acpi_device *adev)
{
	acpi_handle handle = acpi_device_handle(adev);
	union acpi_object *obj;

	conf->adev = adev;

	/* Revision 3 for HID over SPI V1, see specification. */
	obj = acpi_evaluate_dsm_typed(handle, &spi_hid_guid, 3, 1, NULL,
				      ACPI_TYPE_INTEGER);
	if (!obj) {
		acpi_handle_err(handle,
				"Error _DSM call to get HID input report header address failed");
		return -ENODEV;
	}
	conf->property_conf.input_report_header_address = obj->integer.value;
	ACPI_FREE(obj);

	obj = acpi_evaluate_dsm_typed(handle, &spi_hid_guid, 3, 2, NULL,
				      ACPI_TYPE_INTEGER);
	if (!obj) {
		acpi_handle_err(handle,
				"Error _DSM call to get HID input report body address failed");
		return -ENODEV;
	}
	conf->property_conf.input_report_body_address = obj->integer.value;
	ACPI_FREE(obj);

	obj = acpi_evaluate_dsm_typed(handle, &spi_hid_guid, 3, 3, NULL,
				      ACPI_TYPE_INTEGER);
	if (!obj) {
		acpi_handle_err(handle,
				"Error _DSM call to get HID output report header address failed");
		return -ENODEV;
	}
	conf->property_conf.output_report_address = obj->integer.value;
	ACPI_FREE(obj);

	obj = acpi_evaluate_dsm_typed(handle, &spi_hid_guid, 3, 4, NULL,
				      ACPI_TYPE_BUFFER);
	if (!obj) {
		acpi_handle_err(handle,
				"Error _DSM call to get HID read opcode failed");
		return -ENODEV;
	}
	if (obj->buffer.length == 1) {
		conf->property_conf.read_opcode = obj->buffer.pointer[0];
	} else {
		acpi_handle_err(handle,
				"Error _DSM call to get HID read opcode, too long buffer");
		ACPI_FREE(obj);
		return -ENODEV;
	}
	ACPI_FREE(obj);

	obj = acpi_evaluate_dsm_typed(handle, &spi_hid_guid, 3, 5, NULL,
				      ACPI_TYPE_BUFFER);
	if (!obj) {
		acpi_handle_err(handle,
				"Error _DSM call to get HID write opcode failed");
		return -ENODEV;
	}
	if (obj->buffer.length == 1) {
		conf->property_conf.write_opcode = obj->buffer.pointer[0];
	} else {
		acpi_handle_err(handle,
				"Error _DSM call to get HID write opcode, too long buffer");
		ACPI_FREE(obj);
		return -ENODEV;
	}
	ACPI_FREE(obj);

	obj = acpi_evaluate_dsm_typed(handle, &spi_hid_guid, 3, 6, NULL,
				      ACPI_TYPE_INTEGER);
	if (!obj) {
		acpi_handle_err(handle,
				"Error _DSM call to get HID over SPI flags failed");
		return -ENODEV;
	}
	conf->property_conf.flags = obj->integer.value;
	ACPI_FREE(obj);

	/* Value not provided in ACPI,*/
	conf->post_power_on_delay_ms = 5;
	conf->minimal_reset_delay_ms = 150;

	if (!acpi_has_method(handle, "_RST")) {
		acpi_handle_err(handle, "No reset method for acpi handle");
		return -EINVAL;
	}

	return 0;
}

static int spi_hid_acpi_power_none(struct spihid_ops *ops)
{
	return 0;
}

static int spi_hid_acpi_power_down(struct spihid_ops *ops)
{
	struct spi_hid_acpi_config *conf = container_of(ops,
							struct spi_hid_acpi_config,
							ops);

	return acpi_device_set_power(conf->adev, ACPI_STATE_D3);
}

static int spi_hid_acpi_power_up(struct spihid_ops *ops)
{
	struct spi_hid_acpi_config *conf = container_of(ops,
							struct spi_hid_acpi_config,
							ops);
	int error;

	error = acpi_device_set_power(conf->adev, ACPI_STATE_D0);
	if (error) {
		dev_err(&conf->adev->dev, "Error could not power up ACPI device: %d.", error);
		return error;
	}

	if (conf->post_power_on_delay_ms)
		msleep(conf->post_power_on_delay_ms);

	return 0;
}

static int spi_hid_acpi_assert_reset(struct spihid_ops *ops)
{
	return 0;
}

static int spi_hid_acpi_deassert_reset(struct spihid_ops *ops)
{
	struct spi_hid_acpi_config *conf = container_of(ops,
							struct spi_hid_acpi_config,
							ops);

	acpi_status status;

	/*
	 * Not device_reset(&conf->adev->dev): an acpi_device's own struct
	 * device has no ACPI companion, so ACPI_HANDLE() is NULL there and
	 * _RST would never run (the error is ignored by spi-hid-core).
	 */
	status = acpi_evaluate_object(conf->adev->handle, "_RST", NULL, NULL);
	return ACPI_FAILURE(status) ? -EIO : 0;
}

static void spi_hid_acpi_sleep_minimal_reset_delay(struct spihid_ops *ops)
{
	struct spi_hid_acpi_config *conf = container_of(ops,
							struct spi_hid_acpi_config,
							ops);
	fsleep(1000 * conf->minimal_reset_delay_ms);
}

/*
 * Surface Laptop Ultra (NVIDIA N1X): the sensor hub's GpioInt is pin 190 of
 * NVDA9221, an EINT-only line. pinctrl-mt8901 (built in) only has GPIOs
 * 0-181, so the ACPI GpioInt lookup fails, and mtk-eint would refuse
 * request_irq() on the EINT anyway because it locks the matching GPIO.
 *
 * The EINT itself is mapped and works, so drive it directly: take over its
 * flow handler (it is never requested by anyone else), set the trigger type,
 * unmask it, and forward each edge to an interrupt from an irq_sim domain,
 * which spi-hid can request normally. Edges are fed to that interrupt's flow
 * handler directly rather than through irq_sim's pending state: irq_sim drops
 * events while the interrupt is disabled, but the reset response arrives
 * before spi-hid enables it, and genirq keeps it pending and resends it.
 */
#define N1X_EINT_HID	"NVDA9221"
#define N1X_EINT_NUM	190

struct n1x_eint_bridge {
	raw_spinlock_t lock;		/* serialises the handler against teardown */
	bool active;
	struct spi_device *spi;
	unsigned int eint_irq;
	unsigned int sim_irq;
	struct fwnode_handle *sim_fwnode;
	unsigned long edges;
};

static void n1x_eint_flow(struct irq_desc *desc)
{
	struct n1x_eint_bridge *b = irq_desc_get_handler_data(desc);
	struct irq_data *d = irq_desc_get_irq_data(desc);

	d->chip->irq_ack(d);
	raw_spin_lock(&b->lock);
	if (b->active) {
		if (!b->edges++)
			dev_info(&b->spi->dev, "N1X: first EINT edge\n");
		generic_handle_irq_safe(b->sim_irq);
	}
	raw_spin_unlock(&b->lock);
}

static void n1x_eint_bridge_release(void *data)
{
	struct n1x_eint_bridge *b = data;
	struct irq_data *d = irq_get_irq_data(b->eint_irq);
	unsigned long flags;

	d->chip->irq_mask(d);
	raw_spin_lock_irqsave(&b->lock, flags);
	b->active = false;
	raw_spin_unlock_irqrestore(&b->lock, flags);
	dev_info(&b->spi->dev, "N1X: %lu EINT edges forwarded\n", b->edges);
	/* back to what mtk_eint_do_init() installed */
	irq_set_handler(b->eint_irq, handle_level_irq);
	irq_set_handler_data(b->eint_irq, NULL);
	/* the simulated IRQ is about to go away; let the next probe set up a new one */
	b->spi->irq = 0;
}

static void n1x_eint_fwnode_free(void *data)
{
	irq_domain_free_fwnode(data);
}

/* Returns the simulated IRQ to use as spi->irq, or a negative error. */
static int n1x_eint_bridge_setup(struct spi_device *spi)
{
	struct device *dev = &spi->dev;
	struct n1x_eint_bridge *b;
	struct acpi_device *gpio_adev;
	struct irq_domain *eint_dom, *sim_dom;
	struct irq_data *d;
	int ret;

	gpio_adev = acpi_dev_get_first_match_dev(N1X_EINT_HID, NULL, -1);
	if (!gpio_adev)
		return -ENODEV;
	eint_dom = irq_find_matching_fwnode(acpi_fwnode_handle(gpio_adev), DOMAIN_BUS_ANY);
	acpi_dev_put(gpio_adev);
	if (!eint_dom)
		return -EPROBE_DEFER;

	b = devm_kzalloc(dev, sizeof(*b), GFP_KERNEL);
	if (!b)
		return -ENOMEM;
	raw_spin_lock_init(&b->lock);
	b->spi = spi;

	b->eint_irq = irq_find_mapping(eint_dom, N1X_EINT_NUM);
	if (!b->eint_irq)
		return -ENOENT;
	d = irq_get_irq_data(b->eint_irq);
	if (!d || !d->chip || !d->chip->irq_ack || !d->chip->irq_mask || !d->chip->irq_unmask)
		return -ENODEV;
	if (irq_has_action(b->eint_irq))
		return -EBUSY;

	b->sim_fwnode = irq_domain_alloc_named_fwnode("n1x-senh-eint");
	if (!b->sim_fwnode)
		return -ENOMEM;
	ret = devm_add_action_or_reset(dev, n1x_eint_fwnode_free, b->sim_fwnode);
	if (ret)
		return ret;
	sim_dom = devm_irq_domain_create_sim(dev, b->sim_fwnode, 1);
	if (IS_ERR(sim_dom))
		return PTR_ERR(sim_dom);
	b->sim_irq = irq_create_mapping(sim_dom, 0);
	if (!b->sim_irq)
		return -ENOMEM;

	/* GpioInt(Edge, ActiveLow) in SENH._CRS */
	ret = irq_set_irq_type(b->eint_irq, IRQ_TYPE_EDGE_FALLING);
	if (ret)
		return ret;
	irq_set_handler_data(b->eint_irq, b);
	irq_set_handler(b->eint_irq, n1x_eint_flow);
	b->active = true;
	ret = devm_add_action_or_reset(dev, n1x_eint_bridge_release, b);
	if (ret)
		return ret;
	d->chip->irq_ack(d);
	d->chip->irq_unmask(d);

	dev_info(dev, "N1X: EINT %d (irq %u) forwarded to irq %u\n",
		 N1X_EINT_NUM, b->eint_irq, b->sim_irq);
	return b->sim_irq;
}

static int spi_hid_acpi_probe(struct spi_device *spi)
{
	struct device *dev = &spi->dev;
	struct acpi_device *adev;
	struct spi_hid_acpi_config *config;
	int error;

	adev = ACPI_COMPANION(dev);
	if (!adev) {
		dev_err(dev, "Error could not get ACPI device.");
		return -ENODEV;
	}

	config = devm_kzalloc(dev, sizeof(struct spi_hid_acpi_config),
			      GFP_KERNEL);
	if (!config)
		return -ENOMEM;

	if (acpi_device_power_manageable(adev)) {
		config->ops.power_up = spi_hid_acpi_power_up;
		config->ops.power_down = spi_hid_acpi_power_down;
	} else {
		config->ops.power_up = spi_hid_acpi_power_none;
		config->ops.power_down = spi_hid_acpi_power_none;
	}
	config->ops.assert_reset = spi_hid_acpi_assert_reset;
	config->ops.deassert_reset = spi_hid_acpi_deassert_reset;
	config->ops.sleep_minimal_reset_delay =
		spi_hid_acpi_sleep_minimal_reset_delay;

	error = spi_hid_acpi_populate_config(config, adev);
	if (error) {
		dev_err(dev, "%s: unable to populate config data.", __func__);
		return error;
	}

	if (spi->irq <= 0) {
		error = n1x_eint_bridge_setup(spi);
		if (error < 0)
			return dev_err_probe(dev, error, "N1X: no EINT bridge\n");
		spi->irq = error;
	}

	return spi_hid_core_probe(spi, &config->ops, &config->property_conf);
}

static const struct acpi_device_id spi_hid_acpi_match[] = {
	{ "ACPI0C51", 0 },
	{ "PNP0C51", 0 },
	{ }
};
MODULE_DEVICE_TABLE(acpi, spi_hid_acpi_match);

static struct spi_driver spi_hid_acpi_driver = {
	.driver = {
		.name	= "spi_hid_acpi",
		.owner	= THIS_MODULE,
		.pm	= &spi_hid_core_pm,
		.acpi_match_table = spi_hid_acpi_match,
		.probe_type = PROBE_PREFER_ASYNCHRONOUS,
		.dev_groups = spi_hid_groups,
	},
	.probe		= spi_hid_acpi_probe,
	.remove		= spi_hid_core_remove,
};

module_spi_driver(spi_hid_acpi_driver);

MODULE_DESCRIPTION("HID over SPI (core + ACPI glue) for the Surface Laptop Ultra sensor hub");
MODULE_AUTHOR("Angela Czubak <aczubak@google.com>");
MODULE_LICENSE("GPL");
