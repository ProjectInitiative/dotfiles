// SPDX-License-Identifier: GPL-2.0
/*
 * Surface Laptop Ultra (NVIDIA N1X): bring up the camera CCU (Camera Control Unit).
 *
 * The CCU is a MediaTek ISP8 (mt8991-derived) RISC-V core. Its firmware is NVIDIA's
 * own signed image, shipped as nvCCU.img. We do what the vendor's Windows stack
 * does (observed behaviour, see docs/how-it-works.md):
 *
 *   1. power the CCU through the HFRP mailbox (power domains + clocks),
 *   2. initialise the CCU control registers,
 *   3. hand the signed image to ROT0 (the root-of-trust, ACPI NVDA8600) over its
 *      mailbox with command 0x18; ROT0 authenticates it, loads it and releases the
 *      core,
 *   4. complete the boot handshake on the CCU status register.
 *
 * ROT0 verifies NVIDIA's signature, so only the genuine signed image can ever run;
 * this loads firmware, it does not defeat anything. Only command 0x18 is ever sent.
 * Without go=1 the module maps the blocks, reads status and logs what it would do.
 *
 * Firmware: /lib/firmware/nvidia/n1x/nvCCU.img (copy it from the Windows driver store).
 */
#include <linux/acpi.h>
#include <linux/delay.h>
#include <linux/dma-mapping.h>
#include <linux/firmware.h>
#include <linux/io.h>
#include <linux/iopoll.h>
#include <linux/module.h>
#include <linux/platform_device.h>
#include <linux/unaligned.h>

/* ---- HFRP power mailbox ---- */
#define HFRP_BASE	0x31160000
#define HFRP_SIZE	0x204
#define HFRP_MSG_LEN	0x100
#define HFRP_IN_SET	0x100
#define HFRP_OUT_STA	0x104
#define HFRP_OUT_CLR	0x10c
#define HFRP_OK		0x80000000	/* out_sta after a message is accepted */

/* CCU needs seninf power domains 0 and 2 plus the CCU domain 5 */
static const u32 ccu_domains[] = { 0, 2, 5 };
/* seninf clocks 0xa04/0xa09/0xa0a plus the CCU clocks 0x1a00-0x1a04 and 0x652 */
static const u32 ccu_clocks[] = { 0xa04, 0xa09, 0xa0a, 0x1a00, 0x1a01, 0x1a02, 0x1a04, 0x652 };

/* ---- CCU control window ---- */
#define CCU_BASE	0x3c080000
#define CCU_SIZE	0x50000
#define CCU_CTRL	0x30000		/* = 1 */
#define CCU_CTRL_10	0x30010		/* = 6 */
#define CCU_LOG_LEVEL	0x30014		/* = 0 */
#define CCU_PRIVACY	0x3001c		/* = 0 (CCUPrivacyMapping) */
#define CCU_HANDSHAKE	0x30020
#define CCU_INIT_DONE	0xffff0000	/* firmware reached its init point */
#define CCU_READY	0xffff00a5	/* firmware accepted the mailbox, RPCs allowed */

/* ---- ROT0 mailbox ---- */
#define ROT_BASE	0x18010000
#define ROT_WINDOW	0x1000
#define ROT_STRIDE	0x10		/* second memory resource length; register pitch */
/* register index (multiplied by the stride) */
#define ROT_TX_DATA	1	/* +0x10 TX FIFO: header word, then each arg */
#define ROT_TX_READY	2	/* +0x20 bit0: TX FIFO ready */
#define ROT_TX_CTRL	3	/* +0x30 write 3 before, 1 after the args (doorbell) */
#define ROT_RX_DATA	4	/* +0x40 RX FIFO: reply header, then each reply word */
#define ROT_RX_VALID	5	/* +0x50 bit0: a reply is waiting */
#define ROT_RX_ACK	6	/* +0x60 write 1 to consume the reply */
#define ROT_TX_ECHO	7	/* +0x70 each written word read back inverted */
#define ROT_TX_DONE	8	/* +0x80 bit0: TX consumed */
#define ROT_TX_DONE_CLR	9	/* +0x90 write 1 to clear TX-done */
#define ROT_STATUS	11	/* +0xb0 low byte: link status */
#define ROT_CLEAR	12	/* +0xc0 write 0xffffffff before a send */

#define ROT_CMD_LOAD_FW	0x18
#define ROT_TIMEOUT_US	2000000

/* ---- firmware container ---- */
#define FW_NAME		"nvidia/n1x/nvCCU.img"
#define FW_SOC		"mt8991"
#define FW_SLOT		0x20000
#define FW_TYPE		0x000c0300	/* image type word, also ROT arg 0 */

static bool go;
module_param(go, bool, 0444);
MODULE_PARM_DESC(go, "actually power the CCU and send ROT0 command 0x18 (default: dry run)");

struct ccu_boot {
	struct device *dev;
	void __iomem *hfrp;
	void __iomem *ccu;
	void __iomem *rot;
	u32 stride;
	void *fw_buf;
	phys_addr_t fw_phys;
	size_t fw_len;
	u8 *payload;		/* signed image without the type tag (fw_len - 4 bytes) */
};

/* ---------- HFRP power ---------- */

static int hfrp_xfer(struct ccu_boot *cb, const u8 *msg, const char *what)
{
	u32 sta;
	int i, ret;

	for (i = 0; i < 5 && readl(cb->hfrp + HFRP_IN_SET); i++)
		usleep_range(1000, 1200);
	if (readl(cb->hfrp + HFRP_IN_SET)) {
		dev_err(cb->dev, "hfrp: doorbell busy before %s\n", what);
		return -EBUSY;
	}
	memcpy_toio(cb->hfrp, msg, HFRP_MSG_LEN);
	wmb();
	writel(1, cb->hfrp + HFRP_IN_SET);
	ret = readl_poll_timeout(cb->hfrp + HFRP_OUT_STA, sta, sta, 100, 1000000);
	if (ret) {
		dev_err(cb->dev, "hfrp: %s: no reply\n", what);
		return ret;
	}
	writel(sta, cb->hfrp + HFRP_OUT_CLR);
	if (sta != HFRP_OK)
		dev_warn(cb->dev, "hfrp: %s: out_sta 0x%x (expected 0x%x)\n", what, sta, HFRP_OK);
	return 0;
}

static int hfrp_power(struct ccu_boot *cb, u32 domain, bool on)
{
	u8 msg[HFRP_MSG_LEN] = { 1 };
	char what[32];

	put_unaligned_le32(domain, &msg[1]);
	msg[5] = on;
	snprintf(what, sizeof(what), "domain %u %s", domain, on ? "on" : "off");
	return hfrp_xfer(cb, msg, what);
}

static int hfrp_clocks(struct ccu_boot *cb, bool on)
{
	u8 msg[HFRP_MSG_LEN] = { 2 };
	int i;

	for (i = 0; i < ARRAY_SIZE(ccu_clocks); i++)
		put_unaligned_le32(ccu_clocks[i], &msg[1 + 4 * i]);
	msg[81] = on;
	msg[82] = ARRAY_SIZE(ccu_clocks);
	return hfrp_xfer(cb, msg, on ? "clocks on" : "clocks off");
}

static int ccu_power(struct ccu_boot *cb, bool on)
{
	int i, ret;

	if (on) {
		for (i = 0; i < ARRAY_SIZE(ccu_domains); i++) {
			ret = hfrp_power(cb, ccu_domains[i], true);
			if (ret)
				return ret;
		}
		return hfrp_clocks(cb, true);
	}
	hfrp_clocks(cb, false);
	for (i = ARRAY_SIZE(ccu_domains) - 1; i >= 0; i--)
		hfrp_power(cb, ccu_domains[i], false);
	return 0;
}

/* ---------- ROT0 mailbox ---------- */

static u32 rot_rd(struct ccu_boot *cb, int reg)
{
	return readl(cb->rot + reg * cb->stride);
}

static void rot_wr(struct ccu_boot *cb, int reg, u32 val)
{
	writel(val, cb->rot + reg * cb->stride);
	wmb();
}

static int rot_wait(struct ccu_boot *cb, int reg, const char *what)
{
	u32 v;
	int ret = readl_poll_timeout(cb->rot + reg * cb->stride, v, v & 1, 20, ROT_TIMEOUT_US);

	if (ret)
		dev_err(cb->dev, "rot: timeout on %s (+0x%x = 0x%x)\n",
			what, reg * cb->stride, v);
	return ret;
}

/* Send ROT0 command 0x18 {type, len, dma} and return the reply status (0 = ok), or -errno. */
static int rot_load_fw(struct ccu_boot *cb)
{
	u32 args[3] = { FW_TYPE, cb->fw_len, lower_32_bits(cb->fw_phys) };
	u32 hdr = ROT_CMD_LOAD_FW | ARRAY_SIZE(args) << 8;
	u32 reply, status, nreply;
	int i, ret;

	rot_wr(cb, ROT_CLEAR, 0xffffffff);
	rot_wr(cb, ROT_TX_CTRL, 3);

	/* drop any stale reply / done bit left from a previous boot */
	if (rot_rd(cb, ROT_RX_VALID) & 1) {
		rot_wr(cb, ROT_RX_ACK, 1);
		readl_poll_timeout(cb->rot + ROT_RX_VALID * cb->stride, reply,
				   !(reply & 1), 20, ROT_TIMEOUT_US);
	}
	if (rot_rd(cb, ROT_TX_DONE) & 1) {
		rot_wr(cb, ROT_TX_DONE_CLR, 1);
		readl_poll_timeout(cb->rot + ROT_TX_DONE * cb->stride, reply,
				   !(reply & 1), 20, ROT_TIMEOUT_US);
	}

	ret = rot_wait(cb, ROT_TX_READY, "tx-ready (status)");
	if (ret)
		return ret;
	dev_info(cb->dev, "rot: link status 0x%x\n", rot_rd(cb, ROT_STATUS) & 0xff);

	ret = rot_wait(cb, ROT_TX_READY, "tx-ready (data)");
	if (ret)
		return ret;
	rot_wr(cb, ROT_TX_DATA, hdr);
	for (i = 0; i < ARRAY_SIZE(args); i++)
		rot_wr(cb, ROT_TX_DATA, args[i]);
	rot_wr(cb, ROT_TX_CTRL, 1);

	ret = rot_wait(cb, ROT_TX_DONE, "tx-done");
	if (ret)
		return ret;
	/* the mailbox echoes each word back inverted; confirm it took our message */
	if (~rot_rd(cb, ROT_TX_ECHO) != hdr)
		dev_warn(cb->dev, "rot: tx echo mismatch (got ~0x%x, sent 0x%x)\n",
			 ~rot_rd(cb, ROT_TX_ECHO), hdr);

	ret = rot_wait(cb, ROT_RX_VALID, "rx-valid");
	if (ret)
		return ret;
	reply = rot_rd(cb, ROT_RX_DATA);
	nreply = (reply >> 8) & 0xf;
	status = (reply >> 12) & 0xfff;
	for (i = 0; i < nreply; i++)
		dev_info(cb->dev, "rot: reply[%d] = 0x%x\n", i, rot_rd(cb, ROT_RX_DATA));
	rot_wr(cb, ROT_RX_ACK, 1);

	dev_info(cb->dev, "rot: command 0x18 reply header 0x%x, status 0x%x\n", reply, status);
	return status ? -EIO : 0;
}

/* ---------- CCU control + handshake ---------- */

static void ccu_init_regs(struct ccu_boot *cb)
{
	writel(1, cb->ccu + CCU_CTRL);
	writel(6, cb->ccu + CCU_CTRL_10);
	writel(0, cb->ccu + CCU_LOG_LEVEL);
	writel(0, cb->ccu + CCU_PRIVACY);
	wmb();
}

static int ccu_handshake(struct ccu_boot *cb)
{
	u32 v;
	int ret;

	ret = readl_poll_timeout(cb->ccu + CCU_HANDSHAKE, v, v == CCU_INIT_DONE, 100, ROT_TIMEOUT_US);
	if (ret) {
		dev_err(cb->dev, "ccu: init-done timeout (0x%x = 0x%x)\n", CCU_HANDSHAKE, v);
		return ret;
	}
	writel(0, cb->ccu + CCU_HANDSHAKE);
	wmb();
	ret = readl_poll_timeout(cb->ccu + CCU_HANDSHAKE, v, v == CCU_READY, 100, ROT_TIMEOUT_US);
	if (ret) {
		dev_err(cb->dev, "ccu: ready timeout (0x%x = 0x%x)\n", CCU_HANDSHAKE, v);
		return ret;
	}
	dev_info(cb->dev, "ccu: firmware running (handshake 0x%x)\n", v);
	return 0;
}

/* ---------- firmware container ---------- */

/*
 * Copy the mt8991 image out of the nvCCU.img container into a physically contiguous
 * buffer below 4 GB. ROT0 reads it by physical address (its IOMMU domain is identity),
 * and the mailbox doorbell's wmb() orders this copy ahead of the request. If the
 * platform turned out to be non-coherent, ROT would read stale bytes and reject the
 * image rather than run it, so this stays fail-safe.
 */
static int ccu_pick_firmware(struct ccu_boot *cb, const struct firmware *fw)
{
	u32 count, off;
	int i;

	if (fw->size < 4)
		return -EINVAL;
	count = get_unaligned_le32(fw->data);
	if (count > 200 || 4 + count * 10 > fw->size)
		return -EINVAL;
	for (i = 0; i < count; i++) {
		const u8 *ent = fw->data + 4 + i * 10;
		u32 size = get_unaligned_le32(ent + 6);

		if (memcmp(ent, FW_SOC, strlen(FW_SOC)))
			continue;
		off = 4 + count * 10 + i * FW_SLOT;
		if (off + size > fw->size || size < 4)
			return -EINVAL;
		if (get_unaligned_le32(fw->data + off) != FW_TYPE) {
			dev_err(cb->dev, "fw: %s image type 0x%x, expected 0x%x\n", FW_SOC,
				get_unaligned_le32(fw->data + off), FW_TYPE);
			return -EINVAL;
		}
		/*
		 * The first word of the image is the 0x000C0300 type tag, which ROT0 takes
		 * as a separate argument; the signed payload it authenticates is everything
		 * after it. The Windows driver copies input+4 into its DMA buffer and passes
		 * the full size as the length (args = {type, size, pa}).
		 */
		cb->payload = kmemdup(fw->data + off + 4, size - 4, GFP_KERNEL);
		if (!cb->payload)
			return -ENOMEM;
		cb->fw_len = size;
		return 0;
	}
	dev_err(cb->dev, "fw: no %s image in %s\n", FW_SOC, FW_NAME);
	return -ENOENT;
}

/*
 * ROT0 can only DMA from the low part of DRAM: loads from buffers around
 * 0x80a0_0000-0x80e0_0000 succeed while ones near 0xfa00_0000 are refused with
 * status 0x3ff, though IORT advertises 32 bits. The page allocator hands out
 * either, so take a batch of candidates and keep the lowest.
 */
#define FW_CANDIDATES	64
#define FW_TRIES	8

static void *ccu_alloc_low(unsigned int order)
{
	unsigned long cand[FW_CANDIDATES];
	int i, n, best = -1;

	for (n = 0; n < FW_CANDIDATES; n++) {
		cand[n] = __get_free_pages(GFP_KERNEL | GFP_DMA32 | __GFP_ZERO | __GFP_NOWARN,
					   order);
		if (!cand[n])
			break;
		if (best < 0 || virt_to_phys((void *)cand[n]) < virt_to_phys((void *)cand[best]))
			best = n;
	}
	for (i = 0; i < n; i++)
		if (i != best)
			free_pages(cand[i], order);
	return best < 0 ? NULL : (void *)cand[best];
}

/* ---------- driver ---------- */

static int surface_ccu_boot_probe(struct platform_device *pdev)
{
	struct device *dev = &pdev->dev;
	const struct firmware *fw;
	struct ccu_boot *cb;
	int ret;

	cb = devm_kzalloc(dev, sizeof(*cb), GFP_KERNEL);
	if (!cb)
		return -ENOMEM;
	cb->dev = dev;
	cb->stride = ROT_STRIDE;

	cb->hfrp = ioremap(HFRP_BASE, HFRP_SIZE);
	cb->ccu = ioremap(CCU_BASE, CCU_SIZE);
	cb->rot = ioremap(ROT_BASE, ROT_WINDOW);
	if (!cb->hfrp || !cb->ccu || !cb->rot) {
		ret = -ENOMEM;
		goto out_unmap;
	}

	ret = request_firmware(&fw, FW_NAME, dev);
	if (ret) {
		dev_err(dev, "cannot load %s: %d\n", FW_NAME, ret);
		goto out_unmap;
	}
	ret = ccu_pick_firmware(cb, fw);
	release_firmware(fw);
	if (ret)
		goto out_unmap;

	dev_info(dev, "handshake before: 0x%x; %s\n", readl(cb->ccu + CCU_HANDSHAKE),
		 go ? "booting CCU" : "dry run (set go=1 to boot)");
	if (!go) {
		ret = 0;
		goto out_free;
	}

	{
		unsigned int order = get_order(cb->fw_len);
		void *rejected[FW_TRIES];
		int t, nrej = 0;

		for (t = 0; t < FW_TRIES; t++) {
			cb->fw_buf = ccu_alloc_low(order);
			if (!cb->fw_buf) {
				ret = -ENOMEM;
				break;
			}
			cb->fw_phys = virt_to_phys(cb->fw_buf);
			memcpy(cb->fw_buf, cb->payload, cb->fw_len - 4);
			dev_info(dev, "fw: %s image %zu bytes at phys 0x%llx (try %d)\n", FW_SOC,
				 cb->fw_len, (u64)cb->fw_phys, t);
			ret = ccu_power(cb, true);
			if (ret)
				break;
			ccu_init_regs(cb);
			ret = rot_load_fw(cb);
			if (!ret)
				break;
			/* keep the refused buffer so the next pick lands elsewhere */
			rejected[nrej++] = cb->fw_buf;
			cb->fw_buf = NULL;
			ccu_power(cb, false);
		}
		while (nrej--)
			free_pages((unsigned long)rejected[nrej], order);
		kfree(cb->payload);
		cb->payload = NULL;
	}
	if (ret) {
		dev_err(dev, "ROT0 firmware load failed: %d\n", ret);
		goto out_poweroff;
	}
	ret = ccu_handshake(cb);
	if (ret)
		goto out_poweroff;

	platform_set_drvdata(pdev, cb);
	dev_info(dev, "CCU up; leaving it powered\n");
	return 0;

out_poweroff:
	ccu_power(cb, false);
out_free:
	if (cb->fw_buf)
		free_pages((unsigned long)cb->fw_buf, get_order(cb->fw_len));
	kfree(cb->payload);
out_unmap:
	if (cb->rot)
		iounmap(cb->rot);
	if (cb->ccu)
		iounmap(cb->ccu);
	if (cb->hfrp)
		iounmap(cb->hfrp);
	return ret;
}

static const struct acpi_device_id surface_ccu_boot_acpi[] = {
	{ "NVDA8600" },		/* ROT0 */
	{ }
};
MODULE_DEVICE_TABLE(acpi, surface_ccu_boot_acpi);

static struct platform_driver surface_ccu_boot_driver = {
	.probe = surface_ccu_boot_probe,
	.driver = {
		.name = "surface-ccu-boot",
		.acpi_match_table = surface_ccu_boot_acpi,
		.probe_type = PROBE_FORCE_SYNCHRONOUS,
	},
};
module_platform_driver(surface_ccu_boot_driver);

MODULE_DESCRIPTION("Surface Laptop Ultra camera CCU firmware boot (via ROT0)");
MODULE_FIRMWARE(FW_NAME);
MODULE_LICENSE("GPL");
