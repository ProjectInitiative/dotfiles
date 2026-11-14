// SPDX-License-Identifier: GPL-2.0
/*
 * Surface Laptop Ultra (N1X): power button.
 *
 * The buttons sit behind ACPI MSHW0040 (\_SB.MSBT). On x86 Surfaces, soc_button_array turns it
 * into gpio-keys devices, but that driver is x86-only, so on this arm64 machine the power button
 * has no driver. _CRS lists three GpioInt/GpioIo pairs on \_SB.GIO0: pin 46 (power, the only
 * one with SharedAndWake) and pins 40/41. The laptop has no volume rocker, and 40/41 float and
 * report "Volume Down" held forever (teo-casares, omacom/omarchy discussion #15885). This
 * driver only takes pin 46 and reports KEY_POWER; 40/41 are never requested.
 *
 * The idle level is read at probe and treated as "released", since ActiveBoth carries no
 * polarity. A press while suspended only wakes the system and is not reported, so the
 * desktop's power menu does not pop up after resume.
 */
#include <linux/acpi.h>
#include <linux/delay.h>
#include <linux/gpio/consumer.h>
#include <linux/input.h>
#include <linux/interrupt.h>
#include <linux/module.h>
#include <linux/platform_device.h>
#include <linux/pm_wakeup.h>

#define DRV_NAME "n1x-power-button"

struct n1x_pb {
	struct device *dev;
	struct input_dev *input;
	struct gpio_desc *gpio;
	int irq;
	int idle;		/* raw level while released */
	bool pressed;
	bool suspended;
};

static irqreturn_t n1x_pb_irq(int irq, void *data)
{
	struct n1x_pb *pb = data;
	bool pressed;
	int val;

	if (READ_ONCE(pb->suspended)) {
		pm_wakeup_event(pb->dev, 0);
		return IRQ_HANDLED;
	}

	usleep_range(5000, 6000);	/* debounce */
	val = gpiod_get_raw_value_cansleep(pb->gpio);
	if (val < 0)
		return IRQ_HANDLED;
	pressed = val != pb->idle;
	if (pressed != pb->pressed) {
		pb->pressed = pressed;
		input_report_key(pb->input, KEY_POWER, pressed);
		input_sync(pb->input);
	}
	return IRQ_HANDLED;
}

static int n1x_pb_probe(struct platform_device *pdev)
{
	struct device *dev = &pdev->dev;
	struct n1x_pb *pb;
	int ret;

	pb = devm_kzalloc(dev, sizeof(*pb), GFP_KERNEL);
	if (!pb)
		return -ENOMEM;
	pb->dev = dev;

	/* ACPI GPIO index 0 = the first resource, GpioInt pin 46 */
	pb->gpio = devm_gpiod_get_index(dev, NULL, 0, GPIOD_IN);
	if (IS_ERR(pb->gpio))
		return dev_err_probe(dev, PTR_ERR(pb->gpio), "power button gpio\n");
	pb->idle = gpiod_get_raw_value_cansleep(pb->gpio);
	if (pb->idle < 0)
		return dev_err_probe(dev, pb->idle, "read power button\n");

	pb->irq = gpiod_to_irq(pb->gpio);
	if (pb->irq < 0)
		return dev_err_probe(dev, pb->irq, "power button irq\n");

	pb->input = devm_input_allocate_device(dev);
	if (!pb->input)
		return -ENOMEM;
	pb->input->name = "Surface Laptop Ultra Power Button";
	pb->input->phys = DRV_NAME "/input0";
	pb->input->id.bustype = BUS_HOST;
	input_set_capability(pb->input, EV_KEY, KEY_POWER);
	ret = input_register_device(pb->input);
	if (ret)
		return ret;

	ret = devm_request_threaded_irq(dev, pb->irq, NULL, n1x_pb_irq,
					IRQF_TRIGGER_RISING | IRQF_TRIGGER_FALLING | IRQF_ONESHOT,
					DRV_NAME, pb);
	if (ret)
		return dev_err_probe(dev, ret, "request irq %d\n", pb->irq);

	platform_set_drvdata(pdev, pb);
	device_init_wakeup(dev, true);
	dev_info(dev, "power button on irq %d, idle level %d\n", pb->irq, pb->idle);
	return 0;
}

static void n1x_pb_remove(struct platform_device *pdev)
{
	device_init_wakeup(&pdev->dev, false);
}

static int n1x_pb_suspend(struct device *dev)
{
	struct n1x_pb *pb = dev_get_drvdata(dev);

	WRITE_ONCE(pb->suspended, true);
	if (device_may_wakeup(dev))
		enable_irq_wake(pb->irq);
	return 0;
}

static int n1x_pb_resume(struct device *dev)
{
	struct n1x_pb *pb = dev_get_drvdata(dev);

	if (device_may_wakeup(dev))
		disable_irq_wake(pb->irq);
	/*
	 * The press that woke us is not reported. If the button is still held, the release that
	 * follows is a key-up for a key that is not down, which the input core drops.
	 */
	pb->pressed = gpiod_get_raw_value_cansleep(pb->gpio) != pb->idle;
	WRITE_ONCE(pb->suspended, false);
	return 0;
}

static DEFINE_SIMPLE_DEV_PM_OPS(n1x_pb_pm, n1x_pb_suspend, n1x_pb_resume);

static const struct acpi_device_id n1x_pb_acpi_ids[] = {
	{ "MSHW0040" },
	{ }
};
MODULE_DEVICE_TABLE(acpi, n1x_pb_acpi_ids);

static struct platform_driver n1x_pb_driver = {
	.probe = n1x_pb_probe,
	.remove = n1x_pb_remove,
	.driver = {
		.name = DRV_NAME,
		.acpi_match_table = n1x_pb_acpi_ids,
		.pm = pm_sleep_ptr(&n1x_pb_pm),
	},
};
module_platform_driver(n1x_pb_driver);

MODULE_DESCRIPTION("Surface Laptop Ultra (N1X) power button");
MODULE_LICENSE("GPL");
