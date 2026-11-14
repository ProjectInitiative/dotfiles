// SPDX-License-Identifier: GPL-2.0
/*
 * Surface Laptop Ultra (NVIDIA N1X): fix the UART clock of the SAM EC link.
 *
 * The Surface System Aggregator Module (ACPI MSHW0084) talks to the host over
 * the NVDA0240 UART at 4 Mbaud. 8250_mtk has no clock on the ACPI path and
 * assumes a 26 MHz UART input clock, but on N1X the clock is 52 MHz, so the
 * link runs at twice the requested rate and the EC never answers.
 *
 * This module sets the real clock on that one port before the stock
 * surface_aggregator driver opens it. It also works around a 32-bit overflow
 * in mtk8250_set_termios(): "uartclk * 100" wraps for clocks above 42.9 MHz
 * and the fractional divider ends up wrong (3 instead of 0 at 52 MHz and
 * 4 Mbaud). The fractional divider is recomputed with 64-bit math after the
 * stock set_termios has run; once 8250_mtk is fixed this writes the same
 * values again.
 *
 * Nothing in-tree is replaced. Load this before surface_aggregator (modprobe
 * softdep). If surface_aggregator is already loaded but failed to probe, the
 * SAM device is re-probed after the clock has been fixed. While the SAM driver
 * is bound, this module holds a reference on itself so it cannot be removed
 * underneath a running link.
 *
 * The approach (stock SSAM plus a UART clock helper and an MSHW0733 client
 * module) is the one teo-casares described in
 * https://github.com/omacom/omarchy/discussions/15885; the UART clock and the
 * client list come from their Gist
 * https://gist.github.com/teo-casares/8b64949638e1952602a7f435bb34d5b8 and
 * linux-surface. This is an independent implementation of it.
 */

#include <linux/acpi.h>
#include <linux/device.h>
#include <linux/math64.h>
#include <linux/module.h>
#include <linux/mutex.h>
#include <linux/notifier.h>
#include <linux/platform_device.h>
#include <linux/serial_8250.h>
#include <linux/serial_core.h>
#include <linux/tty.h>
#include <linux/tty_port.h>
#include <linux/units.h>

/* Exported by 8250_core, but declared only in drivers/tty/serial/8250/8250.h. */
struct uart_8250_port *serial8250_get_port(int line);

#define N1X_SSAM_HID		"MSHW0084"
#define N1X_UART_HID		"NVDA0240"
#define MTK_ACPI_UARTCLK	(26 * HZ_PER_MHZ)

/* From drivers/tty/serial/8250/8250_mtk.c. */
#define MTK_UART_FRACDIV_L	0x15
#define MTK_UART_FRACDIV_M	0x16

static unsigned int uartclk_hz = 52 * HZ_PER_MHZ;
module_param(uartclk_hz, uint, 0444);
MODULE_PARM_DESC(uartclk_hz, "Real UART input clock of the SAM UART in Hz (default: 52000000)");

struct n1x_uartclk {
	struct device *ssam_dev;	/* serdev device of MSHW0084 */
	struct uart_port *port;
	void (*orig_set_termios)(struct uart_port *port, struct ktermios *termios,
				 const struct ktermios *old);
	unsigned int orig_uartclk;
	bool clk_changed;
	bool pinned;			/* module ref held while SAM is bound */
	struct notifier_block nb;
};

static struct n1x_uartclk n1x;

static void n1x_fixup_fraction(struct uart_port *port, struct ktermios *termios)
{
	/* Same tables as mtk8250_set_termios(). */
	static const unsigned short fraction_l_mapping[] = {
		0, 1, 0x5, 0x15, 0x55, 0x57, 0x57, 0x77, 0x7F, 0xFF, 0xFF
	};
	static const unsigned short fraction_m_mapping[] = {
		0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 3
	};
	unsigned int baud, quot, fraction;
	unsigned long flags;

	/* Below this the stock calculation does not overflow. */
	if (port->uartclk <= UINT_MAX / 100)
		return;

	/* mtk8250_set_termios() leaves the rate it programmed in termios. */
	baud = tty_termios_baud_rate(termios);
	if (baud < 115200)
		return;

	quot = DIV_ROUND_UP(port->uartclk, 256 * baud);
	fraction = div64_u64((u64)port->uartclk * 100, (u64)baud * quot) % 100;
	fraction = DIV_ROUND_CLOSEST(fraction, 10);

	uart_port_lock_irqsave(port, &flags);
	serial_port_out(port, MTK_UART_FRACDIV_L, fraction_l_mapping[fraction]);
	serial_port_out(port, MTK_UART_FRACDIV_M, fraction_m_mapping[fraction]);
	uart_port_unlock_irqrestore(port, flags);
}

static void n1x_set_termios(struct uart_port *port, struct ktermios *termios,
			    const struct ktermios *old)
{
	n1x.orig_set_termios(port, termios, old);
	n1x_fixup_fraction(port, termios);
}

static int n1x_bus_notify(struct notifier_block *nb, unsigned long action, void *data)
{
	struct device *dev = data;

	if (dev != n1x.ssam_dev)
		return NOTIFY_DONE;

	switch (action) {
	case BUS_NOTIFY_BOUND_DRIVER:
		if (!n1x.pinned) {
			__module_get(THIS_MODULE);
			n1x.pinned = true;
		}
		break;
	case BUS_NOTIFY_UNBOUND_DRIVER:
		if (n1x.pinned) {
			n1x.pinned = false;
			module_put(THIS_MODULE);
		}
		break;
	}

	return NOTIFY_OK;
}

static struct device *n1x_find_ssam_dev(void)
{
	struct acpi_device *adev;
	struct device *dev;

	adev = acpi_dev_get_first_match_dev(N1X_SSAM_HID, NULL, -1);
	if (!adev)
		return NULL;

	dev = get_device(acpi_get_first_physical_node(adev));
	acpi_dev_put(adev);
	return dev;
}

static struct uart_port *n1x_find_port(struct device *ssam_dev)
{
	struct device *uart_dev;
	int i;

	/* serdev device -> serdev controller -> serial core devices -> UART */
	for (uart_dev = ssam_dev->parent; uart_dev; uart_dev = uart_dev->parent) {
		if (dev_is_platform(uart_dev) &&
		    acpi_dev_hid_match(ACPI_COMPANION(uart_dev), N1X_UART_HID))
			break;
	}
	if (!uart_dev)
		return NULL;

	for (i = 0; i < CONFIG_SERIAL_8250_NR_UARTS; i++) {
		struct uart_8250_port *up = serial8250_get_port(i);

		if (up->port.dev == uart_dev && up->port.state)
			return &up->port;
	}

	return NULL;
}

static int n1x_apply(struct uart_port *port)
{
	struct tty_port *tport = &port->state->port;
	unsigned long flags;
	int status = 0;

	mutex_lock(&tport->mutex);

	if (tty_port_initialized(tport)) {
		status = -EBUSY;
		goto out;
	}

	if (!port->set_termios) {
		status = -ENODEV;
		goto out;
	}

	uart_port_lock_irqsave(port, &flags);

	n1x.orig_uartclk = port->uartclk;
	if (port->uartclk == MTK_ACPI_UARTCLK && uartclk_hz != port->uartclk) {
		port->uartclk = uartclk_hz;
		n1x.clk_changed = true;
	}

	n1x.orig_set_termios = port->set_termios;
	port->set_termios = n1x_set_termios;

	uart_port_unlock_irqrestore(port, flags);

out:
	mutex_unlock(&tport->mutex);
	return status;
}

static void n1x_restore(struct uart_port *port)
{
	struct tty_port *tport = &port->state->port;
	unsigned long flags;

	mutex_lock(&tport->mutex);

	if (tty_port_initialized(tport))
		dev_warn(port->dev, "port still open, restoring the stock UART clock anyway\n");

	uart_port_lock_irqsave(port, &flags);

	if (port->set_termios == n1x_set_termios)
		port->set_termios = n1x.orig_set_termios;
	if (n1x.clk_changed && port->uartclk == uartclk_hz)
		port->uartclk = n1x.orig_uartclk;

	uart_port_unlock_irqrestore(port, flags);

	mutex_unlock(&tport->mutex);
}

static int __init n1x_uartclk_init(void)
{
	struct device *ssam_dev;
	struct uart_port *port;
	int status;

	ssam_dev = n1x_find_ssam_dev();
	if (!ssam_dev)
		return -ENODEV;

	port = n1x_find_port(ssam_dev);
	if (!port) {
		dev_err(ssam_dev, "no 8250 port found for the %s UART\n", N1X_UART_HID);
		status = -ENODEV;
		goto err_put;
	}

	if (ssam_dev->driver) {
		dev_err(ssam_dev, "SAM already bound to %s; unload it first (stock driver plus this module, or the old patched one)\n",
			ssam_dev->driver->name);
		status = -EBUSY;
		goto err_put;
	}

	n1x.ssam_dev = ssam_dev;
	n1x.port = port;

	/* Before hooking the port, so a concurrent bind is not missed. */
	n1x.nb.notifier_call = n1x_bus_notify;
	status = bus_register_notifier(ssam_dev->bus, &n1x.nb);
	if (status)
		goto err_put;

	status = n1x_apply(port);
	if (status) {
		dev_err(port->dev, "cannot hook the UART: %d\n", status);
		goto err_notifier;
	}

	if (n1x.clk_changed)
		dev_info(port->dev, "SAM UART clock %u -> %u Hz\n",
			 n1x.orig_uartclk, port->uartclk);
	else
		dev_info(port->dev, "SAM UART clock already %u Hz, only fixing the fractional divider\n",
			 port->uartclk);

	/* surface_aggregator may already have tried (and failed) to probe. */
	status = device_attach(ssam_dev);
	if (status < 0)
		dev_warn(ssam_dev, "re-probe failed: %d\n", status);

	return 0;

err_notifier:
	bus_unregister_notifier(ssam_dev->bus, &n1x.nb);
err_put:
	put_device(ssam_dev);
	n1x.ssam_dev = NULL;
	return status;
}
module_init(n1x_uartclk_init);

static void __exit n1x_uartclk_exit(void)
{
	bus_unregister_notifier(n1x.ssam_dev->bus, &n1x.nb);
	n1x_restore(n1x.port);
	put_device(n1x.ssam_dev);
}
module_exit(n1x_uartclk_exit);

MODULE_DESCRIPTION("Surface Laptop Ultra (N1X): 52 MHz UART clock for the SAM EC link");
MODULE_LICENSE("GPL");
