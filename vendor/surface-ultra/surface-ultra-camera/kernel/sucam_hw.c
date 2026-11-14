// SPDX-License-Identifier: GPL-2.0
/*
 * Surface Laptop Ultra camera: hardware bring-up.
 *
 * Path: OV02C10 (i2c, 2-lane D-PHY RAW10) -> CSI PHY0 (rxana via CCU, dphy MMIO)
 * -> mac_csi -> async -> outmux1 -> camsv_b (TAG2/IMG2 WDMA) -> memory.
 * seninf-top/async/rxana are DAPC-protected and only reachable through the CCU
 * firmware (booted by surface_ccu_boot); the stream-on CCU command sequence and
 * the direct-MMIO register state are replayed from a Windows capture.
 */
#include <linux/acpi.h>
#include <linux/delay.h>
#include <linux/io.h>
#include <linux/iopoll.h>
#include <linux/unaligned.h>
#include "sucam.h"
#include "ov02c10_regs.h"
#include "ccu_replay.h"
#include "golden_mmio.h"
#include "golden_omux_all.h"
#include "ir_tables.h"

#define SENSOR_DEV	"i2c-OVTI02C1:00"
#define IR_SENSOR_DEV	"i2c-SMO55F1:00"

#define HFRP_BASE	0x31160000
#define HFRP_SIZE	0x204
#define HFRP_MSG_LEN	0x100
#define HFRP_IN_SET	0x100
#define HFRP_OUT_STA	0x104
#define HFRP_OUT_CLR	0x10c

#define CCU_BASE	0x3c080000
#define CCU_SIZE	0x50000
#define CCU_HANDSHAKE	0x30020
#define CCU_DOORBELL	0x300a0
#define CCU_HDR		0x3c0c8
#define CCU_PAYLOAD	0x3c0e4
#define CCU_READY	0xffff00a5
#define CCU_NO_ACK	0x66669999
#define HDR_FT		0x08
#define HDR_CMD		0x0c
#define HDR_TOKEN	0x10
#define HDR_LEN		0x14
#define HDR_STATUS	0x18
#define CCU_FT_SENINF	4

#define SENINF_MMIO	0x12a10000	/* rxanaA@0 dphy@0x2000 mac_top@0x4000 mac_csi@0x5000 */
#define SENINF_PORT2	0x12a20000	/* same layout, CSI port 2 (IR camera) */
#define OUTMUX_BASE	0x3a100000	/* outmux n @ +n*0x10000 */
#define CAMSV_B		0x3a510000	/* the camsv instance Windows uses */
#define CAMSV_SIZE	0x3000
#define CAM_MAIN	0x3a000000

/* camsv central */
#define SV_SEN_MODE	0x140
#define SV_VF_CON	0x148
#define SV_FORMAT_TAG2	0x594
#define SV_MODULE_DB	0x1b4
#define SV_FBC0_TAG2	0x580
#define SV_FBC1_TAG2	0x584
#define  FBC_EN		BIT(15)
#define  FBC_RESET	BIT(8)
#define  FBC_RCNT_INC	BIT(7)
/* camsv DMATOP (+0x1000) */
#define SV_WDMA_ADDR_IMG2	(0x1000 + 0x240)
#define SV_WDMA_ADDR_MSB_IMG2	(0x1000 + 0x244)
#define SV_WDMA_BASIC_IMG2	(0x1000 + 0x250)

/* ---------- HFRP (power/clock firmware mailbox) ---------- */
static int hfrp_xfer(struct sucam *cam, const u8 *msg)
{
	u32 sta;
	int i, ret;

	for (i = 0; i < 5 && readl(cam->hfrp + HFRP_IN_SET); i++)
		usleep_range(1000, 1200);
	if (readl(cam->hfrp + HFRP_IN_SET))
		return -EBUSY;
	memcpy_toio(cam->hfrp, msg, HFRP_MSG_LEN);
	wmb();
	writel(1, cam->hfrp + HFRP_IN_SET);
	ret = readl_poll_timeout(cam->hfrp + HFRP_OUT_STA, sta, sta, 100, 1000000);
	if (ret)
		return ret;
	writel(sta, cam->hfrp + HFRP_OUT_CLR);
	return 0;
}

static int hfrp_clocks(struct sucam *cam, const u32 *ids, int n, bool on)
{
	u8 msg[HFRP_MSG_LEN] = { 2 };
	int i;

	for (i = 0; i < n; i++)
		put_unaligned_le32(ids[i], &msg[1 + 4 * i]);
	msg[81] = on;
	msg[82] = n;
	return hfrp_xfer(cam, msg);
}

static int hfrp_power(struct sucam *cam, u32 domain, bool on)
{
	u8 msg[HFRP_MSG_LEN] = { 1 };

	put_unaligned_le32(domain, &msg[1]);
	msg[5] = on;
	return hfrp_xfer(cam, msg);
}

static int hfrp_clock_rate(struct sucam *cam, u32 id, u32 mhz)
{
	u8 msg[HFRP_MSG_LEN] = { 3 };

	put_unaligned_le32(id, &msg[1]);
	put_unaligned_le32(mhz, &msg[5]);
	return hfrp_xfer(cam, msg);
}

/* ---------- CCU RPC ---------- */
static int ccu_send(struct sucam *cam, u32 ft, u32 cmd, u32 *buf, u32 len)
{
	void __iomem *h = cam->ccu + CCU_HDR;
	u32 w, status = CCU_NO_ACK;
	int i;

	w = readl(h + 0x00);
	if (w != readl(h + 0x04))
		return -EBUSY;
	for (i = 0; i < len / 4; i++)
		writel(buf[i], cam->ccu + CCU_PAYLOAD + 4 * i);
	writel(CCU_NO_ACK, h + HDR_STATUS);
	writel(ft, h + HDR_FT);
	writel(cmd, h + HDR_CMD);
	writel(CCU_BASE + CCU_PAYLOAD, h + HDR_TOKEN);
	writel(len, h + HDR_LEN);
	wmb();
	writel(w + 1, h + 0x00);
	writel(1, cam->ccu + CCU_DOORBELL);
	for (i = 0; i < 3000; i++) {
		status = readl(h + HDR_STATUS);
		if (status != CCU_NO_ACK)
			break;
		udelay(10);
	}
	if (status == CCU_NO_ACK) {
		writel(w, h + 0x00);
		return -ETIMEDOUT;
	}
	for (i = 0; i < len / 4; i++)
		buf[i] = readl(cam->ccu + CCU_PAYLOAD + 4 * i);
	/* success = status echoes the command */
	return status == cmd ? 0 : -EIO;
}

static const struct ccucmd *replay_table(struct sucam *cam, int *n)
{
	*n = cam->cfg->ir ? ARRAY_SIZE(ir_replay) : ARRAY_SIZE(ccu_replay);
	return cam->cfg->ir ? ir_replay : ccu_replay;
}

static int ccu_replay_range(struct sucam *cam, int from, int to)
{
	const struct ccucmd *t;
	int i, n, ret;

	t = replay_table(cam, &n);
	for (i = from; i < to; i++) {
		const struct ccucmd *c = &t[i];
		u32 buf[16] = { 0 };

		memcpy(buf, c->pl, c->len);
		ret = ccu_send(cam, c->ft, c->cmd, buf, c->len);
		if (ret) {
			dev_err(cam->dev, "ccu replay[%d] ft%u cmd 0x%x: %d\n",
				i, c->ft, c->cmd, ret);
			return ret;
		}
	}
	return 0;
}

static int ccu_set_stream(struct sucam *cam, bool on)
{
	u32 b[2] = { cam->cfg->ir ? IR_SENSOR_ID : 1, on };	/* MSG_SENINF_SET_STREAM {sensor_id, on} */

	return ccu_send(cam, CCU_FT_SENINF, 0x2, b, sizeof(b));
}

/* ---------- sensor (OV02C10 over the ACPI i2c client) ---------- */
static int ov_write(struct sucam *cam, u16 reg, u8 val)
{
	u8 b[3] = { reg >> 8, reg & 0xff, val };
	int ret = i2c_master_send(cam->sensor, b, 3);

	return ret == 3 ? 0 : (ret < 0 ? ret : -EIO);
}

static int ov_read(struct sucam *cam, u16 reg, u8 *val)
{
	u8 wb[2] = { reg >> 8, reg & 0xff };
	struct i2c_msg m[2] = {
		{ .addr = cam->sensor->addr, .len = 2, .buf = wb },
		{ .addr = cam->sensor->addr, .flags = I2C_M_RD, .len = 1, .buf = val },
	};
	int ret = i2c_transfer(cam->sensor->adapter, m, 2);

	return ret == 2 ? 0 : (ret < 0 ? ret : -EIO);
}

int sucam_sensor_set(struct sucam *cam, u32 id, s32 val)
{
	int ret = 0;

	if (cam->cfg->ir)
		return sucam_vd_set(cam, id, val);
	if (!cam->powered)
		return 0;	/* applied at next stream start */
	switch (id) {
	case V4L2_CID_EXPOSURE:		/* 16-bit lines @0x3501 */
		ret |= ov_write(cam, 0x3501, val >> 8);
		ret |= ov_write(cam, 0x3502, val & 0xff);
		break;
	case V4L2_CID_ANALOGUE_GAIN:	/* 16-bit @0x3508 = gain << 4 */
		ret |= ov_write(cam, 0x3508, (val << 4) >> 8);
		ret |= ov_write(cam, 0x3509, (val << 4) & 0xff);
		break;
	case V4L2_CID_DIGITAL_GAIN:	/* 24-bit @0x350a = gain << 6 */
		ret |= ov_write(cam, 0x350a, (val << 6) >> 16);
		ret |= ov_write(cam, 0x350b, ((val << 6) >> 8) & 0xff);
		ret |= ov_write(cam, 0x350c, (val << 6) & 0xff);
		break;
	case V4L2_CID_VBLANK:		/* frame length (VTS) @0x380e */
		ret |= ov_write(cam, 0x380e, cam->vts >> 8);
		ret |= ov_write(cam, 0x380f, cam->vts & 0xff);
		break;
	case V4L2_CID_HBLANK:		/* read-only description of the mode */
	case V4L2_CID_PIXEL_RATE:
	case V4L2_CID_CAMERA_ORIENTATION:
	case V4L2_CID_CAMERA_SENSOR_ROTATION:
		break;
	default:
		return -EINVAL;
	}
	return ret ? -EIO : 0;
}

static int sensor_power(struct sucam *cam, bool on)
{
	u8 idh = 0, idl = 0;
	int i;

	if (cam->cfg->ir)
		return sucam_vd_power(cam, on);
	if (!on) {
		gpiod_set_value_cansleep(cam->gpio[SUCAM_GPIO_RESET], 1);
		gpiod_set_value_cansleep(cam->gpio[SUCAM_GPIO_PLED], 0);
		for (i = SUCAM_GPIO_MCLK; i >= SUCAM_GPIO_CAMPOWER; i--)
			gpiod_set_value_cansleep(cam->gpio[i], 0);
		cam->powered = false;
		return 0;
	}
	for (i = SUCAM_GPIO_CAMPOWER; i <= SUCAM_GPIO_MCLK; i++) {
		gpiod_set_value_cansleep(cam->gpio[i], 1);
		usleep_range(5000, 6000);
	}
	gpiod_set_value_cansleep(cam->gpio[SUCAM_GPIO_RESET], 0);	/* deassert */
	usleep_range(10000, 12000);
	gpiod_set_value_cansleep(cam->gpio[SUCAM_GPIO_PLED], 1);
	cam->powered = true;

	if (ov_read(cam, 0x300a, &idh) || ov_read(cam, 0x300b, &idl) ||
	    idh != 0x56 || idl != 0x02) {
		dev_err(cam->dev, "OV02C10 not responding (id %02x%02x)\n", idh, idl);
		sensor_power(cam, false);
		return -ENODEV;
	}
	return 0;
}

static int sensor_stream(struct sucam *cam, bool on)
{
	int i, ret;

	if (cam->cfg->ir)
		return sucam_vd_stream(cam, on);
	if (!on)
		return ov_write(cam, 0x0100, 0x00);
	for (i = 0; i < ARRAY_SIZE(ov02c10_base); i++) {
		ret = ov_write(cam, ov02c10_base[i].addr, ov02c10_base[i].val);
		if (ret)
			return ret;
	}
	for (i = 0; i < ARRAY_SIZE(ov02c10_2lane); i++) {
		ret = ov_write(cam, ov02c10_2lane[i].addr, ov02c10_2lane[i].val);
		if (ret)
			return ret;
	}
	ret = v4l2_ctrl_handler_setup(&cam->ctrls);	/* exposure / gains (own lock) */
	if (ret)
		return ret;
	return ov_write(cam, 0x0100, 0x01);
}

/* ---------- seninf / outmux / camsv (direct MMIO) ---------- */

/*
 * All non-waived outmuxes to the Windows streaming state. The firmware's
 * path-enable reads SRC_SEL (+0x18) and skips sen_sel >= 2, so the used ones
 * (1, 7) must be 0 and the unused ones are parked at 3. outmux registers are
 * double-buffered (cfg_mode NORMAL): SW_CFG_DONE (+0x1c) latches them.
 */
/*
 * Front camera at the full sensor width. Windows streams 1920x1080, which is
 * what the golden tables hold; these widen the outmux tag sizes and the camsv
 * grab to SUCAM_W (sucam.h says why). Same registers the IR path overrides.
 */
#define OMUX_TAG_SIZE(w, h)	((((h) - 1) << 16) | ((w) - 1))	/* 0x0437077f at 1920x1080 */
#define OMUX_TAG_WH(w, h)	(((w) << 16) | (h))		/* 0x07800438 at 1920x1080 */
static const struct omw front_omux[] = {
	{ 1, 0x0a0, OMUX_TAG_SIZE(SUCAM_W, SUCAM_H) },
	{ 1, 0x0ac, OMUX_TAG_WH(SUCAM_W, SUCAM_H) },
	{ 7, 0x084, OMUX_TAG_SIZE(SUCAM_W, SUCAM_H) },
	{ 7, 0x090, OMUX_TAG_WH(SUCAM_W, SUCAM_H) },
};
static const struct rw front_camsv[] = {
	{ 0x0588, SUCAM_W << 16 },	/* GRAB_PXL_TAG2 = end << 16 | start */
	{ 0x058c, SUCAM_H << 16 },	/* GRAB_LIN_TAG2 (unchanged) */
};

static void outmux_setup(struct sucam *cam)
{
	static const u8 nonwaived[] = { 0, 1, 4, 6, 7, 9, 11, 13 };
	void __iomem *oa = ioremap(OUTMUX_BASE, 0xe0000);
	int k;

	if (!oa)
		return;
	for (k = 0; k < ARRAY_SIZE(g_omux_all); k++)
		writel(g_omux_all[k].val, oa + g_omux_all[k].mux * 0x10000 + g_omux_all[k].off);
	if (cam->cfg->ir)		/* outmux1 from async 2, 600x600 */
		for (k = 0; k < ARRAY_SIZE(ir_omux); k++)
			writel(ir_omux[k].val, oa + IR_OUTMUX * 0x10000 + ir_omux[k].off);
	else
		for (k = 0; k < ARRAY_SIZE(front_omux); k++)
			writel(front_omux[k].val, oa + front_omux[k].mux * 0x10000 + front_omux[k].off);
	wmb();
	for (k = 0; k < ARRAY_SIZE(nonwaived); k++)
		writel(1, oa + nonwaived[k] * 0x10000 + 0x1c);
	wmb();
	iounmap(oa);
}

static void writes(void __iomem *base, const struct rw *t, int n)
{
	int i;

	for (i = 0; i < n; i++)
		writel(t[i].val, base + t[i].off);
}

static void phy_mac_setup(struct sucam *cam)
{
	void __iomem *sn = ioremap(cam->cfg->ir ? SENINF_PORT2 : SENINF_MMIO, 0x8000);
	void __iomem *dp, *mt, *mc;
	int i;

	if (!sn)
		return;
	dp = sn + 0x2000;
	mt = sn + 0x4000;
	mc = sn + 0x5000;
	writel(1, mt + 0x00);		/* mac SW reset */
	wmb();
	udelay(10);
	writel(0, mt + 0x00);
	writel(0, dp + 0x08);
	if (cam->cfg->ir) {		/* port 2, 1 lane (ir_tables.h) */
		writes(dp, ir_dphy, ARRAY_SIZE(ir_dphy));
		writes(mt, ir_mactop, ARRAY_SIZE(ir_mactop));
		writes(mc, ir_maccsi, ARRAY_SIZE(ir_maccsi));
		wmb();
		writel(P2_CSI2_EN, mc + 0x00);
		wmb();
		iounmap(sn);
		return;
	}
	for (i = 0; i < ARRAY_SIZE(g_dphy); i++)
		writel(g_dphy[i].val, dp + g_dphy[i].off);
	writel(0x00000001, dp + 0x184);
	writel(0x01050701, dp + 0x188);
	for (i = 0; i < ARRAY_SIZE(g_mactop); i++)
		writel(g_mactop[i].val, mt + g_mactop[i].off);
	writel(0x00308408, mc + 0x14);
	for (i = 1; i < ARRAY_SIZE(g_maccsi); i++)	/* +0x00 (CSI2_EN) last */
		writel(g_maccsi[i].val, mc + g_maccsi[i].off);
	wmb();
	writel(0x3, mc + 0x00);
	wmb();
	iounmap(sn);
}

/*
 * Reset camsv_b (MTK mtk_cam-sv.c sv_reset + sv_reset_by_camsys_top): DMA top,
 * central and CQ DMA soft resets, then the camsys-level reset of this camsv.
 * A bad configuration (e.g. FORMAT_TAG2 = RAW12 against a RAW10 sensor) leaves
 * camsv dropping every frame until it is reset. MediaTek only resets on error
 * recovery, and resetting at every stream start hung the machine twice while
 * the IR camera was started and stopped repeatedly, so only reset after a
 * stream that delivered no frame (camsv_b is shared by both cameras).
 */
static int sv_reset = 1;
module_param(sv_reset, int, 0644);
MODULE_PARM_DESC(sv_reset, "reset camsv at stream start: 0 never, 1 after a stream without frames, 2 always");
static bool camsv_suspect;

void sucam_hw_stream_result(struct sucam *cam, u32 frames)
{
	camsv_suspect = !frames;
}

#define SV_DMATOP_SW_RST	(0x1000 + 0x020)
#define SV_CENTRAL_DCM_DIS	0x07c
#define SV_CENTRAL_SW_CTL	0x1d0
#define SV_SCQ_SW_RST		(0x2000 + 0x010)
#define CAM_MAIN_SW_RST_1	0x058
#define CAMSV_B_ID		1

static void camsv_reset(struct sucam *cam)
{
	void __iomem *sv = cam->sv, *cm;
	u32 v;
	int r1, r2;

	writel(readl(sv + SV_SEN_MODE) & ~BIT(0), sv + SV_SEN_MODE);
	writel(readl(sv + SV_VF_CON) & ~BIT(0), sv + SV_VF_CON);

	writel(0, sv + SV_DMATOP_SW_RST);
	writel(1, sv + SV_DMATOP_SW_RST);
	wmb();
	r1 = readl_poll_timeout(sv + SV_DMATOP_SW_RST, v, v & 2, 1, 100000);
	writel(0, sv + SV_CENTRAL_DCM_DIS);
	writel(0, sv + SV_CENTRAL_SW_CTL);
	writel(1, sv + SV_CENTRAL_SW_CTL);
	writel(0, sv + SV_DMATOP_SW_RST);
	writel(0, sv + SV_CENTRAL_SW_CTL);
	wmb();

	writel(0, sv + SV_SCQ_SW_RST);
	writel(1, sv + SV_SCQ_SW_RST);
	wmb();
	r2 = readl_poll_timeout(sv + SV_SCQ_SW_RST, v, v & 2, 1, 100000);
	writel(0, sv + SV_SCQ_SW_RST);

	cm = ioremap(CAM_MAIN, 0x1000);
	if (cm) {
		writel(0, cm + CAM_MAIN_SW_RST_1);
		writel(3 << (CAMSV_B_ID * 2), cm + CAM_MAIN_SW_RST_1);
		writel(0, cm + CAM_MAIN_SW_RST_1);
		iounmap(cm);
	}
	wmb();
	dev_info(cam->dev, "camsv reset: dma %s, cq %s\n",
		 r1 ? "timeout" : "ok", r2 ? "timeout" : "ok");
}

static void camsv_setup(struct sucam *cam, dma_addr_t addr)
{
	void __iomem *sv = cam->sv, *cm;
	int i;

	if (sv_reset == 2 || (sv_reset == 1 && camsv_suspect))
		camsv_reset(cam);
	camsv_suspect = false;

	for (i = 0; i < ARRAY_SIZE(g_camsv1); i++)
		writel(g_camsv1[i].val, sv + g_camsv1[i].off);
	for (i = 0; i < ARRAY_SIZE(g_camsv1dma); i++)
		writel(g_camsv1dma[i].val, sv + g_camsv1dma[i].off);
	if (cam->cfg->ir)		/* grab size 600x600 */
		writes(sv, ir_camsv_override, ARRAY_SIZE(ir_camsv_override));
	else
		writes(sv, front_camsv, ARRAY_SIZE(front_camsv));
	writel(cam->fmt->sv_fmt, sv + SV_FORMAT_TAG2);
	/* per-frame DMA regs (Windows writes these via CQ into the inner bank) */
	writel(lower_32_bits(addr), sv + SV_WDMA_ADDR_IMG2);
	writel(upper_32_bits(addr), sv + SV_WDMA_ADDR_MSB_IMG2);
	writel((cam->fmt->stride << 16) | 0x10, sv + SV_WDMA_BASIC_IMG2);
	writel(FBC_EN, sv + SV_FBC0_TAG2);
	writel(FBC_EN | FBC_RCNT_INC, sv + SV_FBC0_TAG2);	/* 1 buffer available */
	wmb();
	cm = ioremap(CAM_MAIN, 0x1000);
	if (cm) {
		writel(0x67, cm + 0x590);	/* LARB13_VC_SEL (smi vc for camsv id1) */
		iounmap(cm);
	}
	/* load the double-buffered config, then CMOS_EN / VFDATA_EN */
	writel(readl(sv + SV_MODULE_DB) & ~BIT(30), sv + SV_MODULE_DB);
	wmb();
	writel(readl(sv + SV_MODULE_DB) | BIT(30), sv + SV_MODULE_DB);
	writel(readl(sv + SV_SEN_MODE) | BIT(0), sv + SV_SEN_MODE);
	writel(readl(sv + SV_VF_CON) | BIT(0), sv + SV_VF_CON);
	wmb();
}

static void camsv_stop(struct sucam *cam)
{
	void __iomem *sv = cam->sv;

	writel(readl(sv + SV_VF_CON) & ~BIT(0), sv + SV_VF_CON);
	writel(readl(sv + SV_SEN_MODE) & ~BIT(0), sv + SV_SEN_MODE);
	writel(0, sv + 0x040);			/* DMA_EN_IMG */
	writel(FBC_RESET, sv + SV_FBC0_TAG2);
	writel(readl(sv + SV_MODULE_DB) & ~BIT(30), sv + SV_MODULE_DB);
	wmb();
	writel(readl(sv + SV_MODULE_DB) | BIT(30), sv + SV_MODULE_DB);
}

/* program the next buffer; latched at the next frame start (DB), + 1 FBC slot */
void sucam_hw_arm(struct sucam *cam, dma_addr_t addr)
{
	writel(lower_32_bits(addr), cam->sv + SV_WDMA_ADDR_IMG2);
	writel(upper_32_bits(addr), cam->sv + SV_WDMA_ADDR_MSB_IMG2);
	wmb();
	writel(FBC_EN | FBC_RCNT_INC, cam->sv + SV_FBC0_TAG2);
}

/* one-line hardware state, logged by the poll thread while no frames arrive */
void sucam_hw_diag(struct sucam *cam)
{
	void __iomem *sn = ioremap((cam->cfg->ir ? SENINF_PORT2 : SENINF_MMIO) + 0x5000, 0x100);
	void __iomem *om = ioremap(OUTMUX_BASE + 0x10000, 0x100);
	void __iomem *sv = cam->sv;

	dev_info(cam->dev,
		 "diag: mac d4=%08x dc=%08x | omux1 1c=%x 28=%08x | sv sen=%x vf=%x fbc=%08x/%08x addr=%08x\n",
		 sn ? readl(sn + 0xd4) : 0, sn ? readl(sn + 0xdc) : 0,
		 om ? readl(om + 0x1c) : 0, om ? readl(om + 0x28) : 0,
		 readl(sv + SV_SEN_MODE), readl(sv + SV_VF_CON),
		 readl(sv + SV_FBC0_TAG2), readl(sv + SV_FBC1_TAG2),
		 readl(sv + SV_WDMA_ADDR_IMG2));
	if (sn)
		iounmap(sn);
	if (om)
		iounmap(om);
}

/* SOF of TAG2 since the last call (SOF_STATUS is read-to-clear, tag n = bit 2+4n) */
bool sucam_hw_sof(struct sucam *cam)
{
	return readl(cam->sv + 0x360) & BIT(6);
}

u8 sucam_hw_wcnt(struct sucam *cam)
{
	return (readl(cam->sv + SV_FBC1_TAG2) >> 8) & 0xff;
}

/* is data reaching outmux1? its path debug port (+0x28) moves while frames pass */
static bool outmux1_flowing(void)
{
	void __iomem *om = ioremap(OUTMUX_BASE + 0x10000, 0x100);
	bool moved = false;
	u32 v0;
	int i;

	if (!om)
		return true;
	v0 = readl(om + 0x28);
	for (i = 0; i < 30 && !moved; i++) {
		msleep(10);
		moved = readl(om + 0x28) != v0;
	}
	iounmap(om);
	return moved;
}

static int hw_start_once(struct sucam *cam, dma_addr_t first);
static void hw_stop(struct sucam *cam);

/*
 * The first stream after the CCU firmware boots never gets routed (mac decodes,
 * outmux stays idle); the same sequence works from the second time on. So
 * check that data reaches outmux1 and redo the bring-up once if it does not.
 */
/*
 * Both cameras end in outmux1 -> camsv_b and share the HFRP and CCU mailboxes:
 * one stream at a time.
 */
static DEFINE_MUTEX(path_lock);
static struct sucam *path_owner;

static int hw_start_locked(struct sucam *cam, dma_addr_t first);

int sucam_hw_start(struct sucam *cam, dma_addr_t first)
{
	int ret;

	mutex_lock(&path_lock);
	if (path_owner && path_owner != cam) {
		mutex_unlock(&path_lock);
		dev_info(cam->dev, "the other camera is streaming\n");
		return -EBUSY;
	}
	ret = hw_start_locked(cam, first);
	path_owner = ret ? NULL : cam;
	mutex_unlock(&path_lock);
	return ret;
}

static int hw_start_locked(struct sucam *cam, dma_addr_t first)
{
	int ret = hw_start_once(cam, first);

	if (ret || outmux1_flowing())
		return ret;
	dev_info(cam->dev, "no data through outmux1, restarting the stream once\n");
	hw_stop(cam);
	ret = hw_start_once(cam, first);
	if (!ret && !outmux1_flowing())
		dev_warn(cam->dev, "still no data through outmux1\n");
	return ret;
}

/*
 * The HFRP firmware counts "on" requests, and the driver never sends "off"
 * (whether "off" is counted or absolute is unknown, and the CCU needs these
 * clocks). Sending them at every stream start made the counts overflow: about
 * the 63rd start of a boot timed out in the HFRP mailbox ("HFRP clocks: -110")
 * and the SoC reset itself a minute later (BERT MTKID record, byte 0x2c =
 * 0x0400). So request everything once per power cycle of the camera island:
 * at the first stream after boot or after a system suspend.
 */
static bool hfrp_common_on;	/* domains, CCU + camsv clocks */
static bool hfrp_phy_on[2];	/* CSI PHY clock + rate, [0] front, [1] IR */

void sucam_hw_power_lost(void)
{
	hfrp_common_on = false;
	hfrp_phy_on[0] = hfrp_phy_on[1] = false;
}

static int hfrp_request_once(struct sucam *cam)
{
	/* camsv_a + camsv_b (clarb13 0xa00, camsv_b 0xa18) and the CAM main clocks */
	static const u32 sv_clks[] = { 0xa01, 0xa0b, 0xa10, 0xa11, 0xa12, 0xa13,
				       0xa17, 0xa00, 0xa18 };
	/* seninf + CCU power domains and the CCU/seninf clocks (as surface_ccu_boot) */
	static const u32 domains[] = { 0, 2, 5 };
	static const u32 ccu_clks[] = { 0xa04, 0xa09, 0xa0a, 0x1a00, 0x1a01, 0x1a02, 0x1a04,
					0x652 };
	bool ir = cam->cfg->ir;
	int i, ret = 0;

	/*
	 * The camera island must be powered BEFORE any of its MMIO is touched:
	 * after a system suspend it is off, and a read of a powered-off block
	 * stalls the bus (unkillable task).
	 */
	if (!hfrp_common_on) {
		for (i = 0; i < ARRAY_SIZE(domains) && !ret; i++)
			ret = hfrp_power(cam, domains[i], true);
		ret = ret ?: hfrp_clocks(cam, ccu_clks, ARRAY_SIZE(ccu_clks), true);
		ret = ret ?: hfrp_clocks(cam, sv_clks, ARRAY_SIZE(sv_clks), true);
		if (ret) {
			dev_err(cam->dev, "HFRP power: %d\n", ret);
			return ret;
		}
		hfrp_common_on = true;
	}

	/* CSI PHY clock (0x813 + port) and its rate (id 6 + port) */
	if (!hfrp_phy_on[ir]) {
		ret = hfrp_clocks(cam, (u32[]){ ir ? 0x815 : 0x813 }, 1, true);
		ret = ret ?: hfrp_clock_rate(cam, ir ? 8 : 6, 312);
		if (ret) {
			dev_err(cam->dev, "HFRP clocks: %d\n", ret);
			return ret;
		}
		hfrp_phy_on[ir] = true;
	}
	return 0;
}

static int hw_start_once(struct sucam *cam, dma_addr_t first)
{
	const struct ccucmd *t;
	int ss, n, ret;

	ret = hfrp_request_once(cam);
	if (ret)
		return ret;
	if (readl(cam->ccu + CCU_HANDSHAKE) != CCU_READY) {
		dev_err(cam->dev, "CCU firmware not running (load surface_ccu_boot go=1)\n");
		return -EIO;
	}
	t = replay_table(cam, &n);
	for (ss = 0; ss < n; ss++)
		if (t[ss].ft == CCU_FT_SENINF && t[ss].cmd == 0x1)
			break;	/* MSG_SENINF_SET_SENSOR */

	ret = sensor_power(cam, true);
	if (ret)
		return ret;

	outmux_setup(cam);
	ret = ccu_replay_range(cam, 0, ss);	/* iomem, common reg, rxana, async */
	if (!ret && cam->cfg->ir) {
		u32 om = IR_OUTMUX;

		/* outmux clock on before it is configured (the replay gated it) */
		ret = ccu_send(cam, CCU_FT_SENINF, 0x83, &om, sizeof(om));
	}
	if (ret)
		goto err_power;
	phy_mac_setup(cam);
	outmux_setup(cam);
	camsv_setup(cam, first);
	ret = sensor_stream(cam, true);		/* path must be live before SET_SENSOR */
	if (ret)
		goto err_power;
	msleep(40);
	ret = ccu_replay_range(cam, ss, n);	/* SET_SENSOR, outmux CG, SET_STREAM */
	if (ret)
		goto err_stream;
	readl(cam->sv + 0x360);		/* drop stale SOF status (read-to-clear) */
	cam->last_wcnt = sucam_hw_wcnt(cam);
	return 0;

err_stream:
	sensor_stream(cam, false);
err_power:
	camsv_stop(cam);
	sensor_power(cam, false);
	return ret;
}

static void hw_stop(struct sucam *cam)
{
	camsv_stop(cam);
	ccu_set_stream(cam, false);
	sensor_stream(cam, false);
	sensor_power(cam, false);
}

void sucam_hw_stop(struct sucam *cam)
{
	mutex_lock(&path_lock);
	if (path_owner == cam) {
		hw_stop(cam);
		path_owner = NULL;
	}
	mutex_unlock(&path_lock);
}

/* ---------- resources ---------- */
static const struct acpi_gpio_params campower_gpio = { 0, 0, false };
static const struct acpi_gpio_params avdd_gpio = { 1, 0, false };
static const struct acpi_gpio_params reset_gpio = { 2, 0, true };
static const struct acpi_gpio_params mclk_gpio = { 3, 0, false };
static const struct acpi_gpio_params pled_gpio = { 4, 0, false };
static const struct acpi_gpio_params ir_pled_gpio = { 3, 0, false };	/* same pin 43 */

/* \_SB.CAMF lists its GPIOs by position only; names come from a vendor _DSM */
static const struct acpi_gpio_mapping sucam_gpios[] = {
	{ "campower-gpios", &campower_gpio, 1 },
	{ "avdd-gpios", &avdd_gpio, 1 },
	{ "reset-gpios", &reset_gpio, 1 },
	{ "mclk-gpios", &mclk_gpio, 1 },
	{ "pled-gpios", &pled_gpio, 1 },
	{ }
};

static const char * const sucam_gpio_names[SUCAM_GPIO_NUM] = {
	[SUCAM_GPIO_CAMPOWER] = "campower", [SUCAM_GPIO_AVDD] = "avdd",
	[SUCAM_GPIO_MCLK] = "mclk", [SUCAM_GPIO_RESET] = "reset",
	[SUCAM_GPIO_PLED] = "pled",
};

/*
 * \_SB.CAMI (IR): campower, avdd, reset, pled. No mclk (the sensor has its own
 * oscillator); pled is the front camera's LED pin, which the front device holds.
 */
static const struct acpi_gpio_mapping sucam_ir_gpios[] = {
	{ "campower-gpios", &campower_gpio, 1 },
	{ "avdd-gpios", &avdd_gpio, 1 },
	{ "reset-gpios", &reset_gpio, 1 },
	{ "pled-gpios", &ir_pled_gpio, 1 },
	{ }
};

int sucam_hw_init(struct sucam *cam)
{
	struct acpi_device *adev;
	int i, ret;

	cam->sensor_dev = bus_find_device_by_name(&i2c_bus_type, NULL,
						  cam->cfg->ir ? IR_SENSOR_DEV : SENSOR_DEV);
	if (!cam->sensor_dev)
		return -EPROBE_DEFER;	/* i2c controller not probed yet (early boot) */
	cam->sensor = i2c_verify_client(cam->sensor_dev);
	adev = ACPI_COMPANION(cam->sensor_dev);
	if (!cam->sensor || !adev) {
		ret = -ENODEV;
		goto err_put;
	}
	ret = acpi_dev_add_driver_gpios(adev, cam->cfg->ir ? sucam_ir_gpios : sucam_gpios);
	if (ret)
		goto err_put;
	for (i = 0; i < SUCAM_GPIO_NUM; i++) {
		if (cam->cfg->ir && i == SUCAM_GPIO_MCLK)
			continue;	/* the IR camera has its own oscillator (NULL = no-op) */
		/*
		 * logical 0 = off; reset is active-low so 1 = held in reset. Both
		 * cameras list pled (pin 43); they never stream at the same time.
		 */
		cam->gpio[i] = gpiod_get(cam->sensor_dev, sucam_gpio_names[i],
					 i == SUCAM_GPIO_RESET ? GPIOD_OUT_HIGH :
					 i == SUCAM_GPIO_PLED ?
					 GPIOD_OUT_LOW | GPIOD_FLAGS_BIT_NONEXCLUSIVE :
					 GPIOD_OUT_LOW);
		if (IS_ERR(cam->gpio[i])) {
			ret = PTR_ERR(cam->gpio[i]);
			dev_err(cam->dev, "%s gpio: %d\n", sucam_gpio_names[i], ret);
			cam->gpio[i] = NULL;
			goto err_gpio;
		}
	}

	cam->hfrp = ioremap(HFRP_BASE, HFRP_SIZE);
	cam->ccu = ioremap(CCU_BASE, CCU_SIZE);
	cam->sv = ioremap(CAMSV_B, CAMSV_SIZE);
	if (!cam->hfrp || !cam->ccu || !cam->sv) {
		ret = -ENOMEM;
		goto err_map;
	}
	return 0;

err_map:
	sucam_hw_exit(cam);
	return ret;
err_gpio:
	while (--i >= 0)
		if (cam->gpio[i])
			gpiod_put(cam->gpio[i]);
	acpi_dev_remove_driver_gpios(adev);
err_put:
	put_device(cam->sensor_dev);
	cam->sensor_dev = NULL;
	return ret;
}

void sucam_hw_exit(struct sucam *cam)
{
	int i;

	if (cam->sv)
		iounmap(cam->sv);
	if (cam->ccu)
		iounmap(cam->ccu);
	if (cam->hfrp)
		iounmap(cam->hfrp);
	cam->sv = cam->ccu = cam->hfrp = NULL;
	for (i = 0; i < SUCAM_GPIO_NUM; i++) {
		if (cam->gpio[i]) {
			/* leave everything off (pins keep their level after release) */
			gpiod_set_value_cansleep(cam->gpio[i], i == SUCAM_GPIO_RESET);
			gpiod_put(cam->gpio[i]);
			cam->gpio[i] = NULL;
		}
	}
	if (cam->sensor_dev) {
		acpi_dev_remove_driver_gpios(ACPI_COMPANION(cam->sensor_dev));
		put_device(cam->sensor_dev);
		cam->sensor_dev = NULL;
	}
}
