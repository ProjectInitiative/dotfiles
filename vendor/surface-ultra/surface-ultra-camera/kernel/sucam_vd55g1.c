// SPDX-License-Identifier: GPL-2.0
/*
 * Surface Laptop Ultra IR camera sensor: ST VD55G1 (mono, global shutter) on ACPI CAMI.
 *
 * Power-up follows drivers/media/i2c/vd55g1.c (wait READY_TO_BOOT, EXT_CLOCK, firmware
 * patch 2.9, boot to SW_STBY). The mode is the register list of the Windows sensor driver
 * (12 MHz, 1086 Mbps on one lane, 600x600 RAW10, IR LED strobed from sensor GPIO2), changed
 * to a single context (Windows alternates two, for face authentication) at 30 fps, with a
 * fixed exposure in the IR LED's range by default (sucam.h).
 */
#include <linux/delay.h>
#include <linux/i2c.h>
#include <linux/iopoll.h>
#include <linux/unaligned.h>
#include "sucam.h"
#include "vd55g1_patch.h"
#include "vd55g1_windows.h"

#define VD_FSM			0x001c
#define  FSM_READY_TO_BOOT	1
#define  FSM_SW_STBY		2
#define  FSM_STREAMING		3
#define VD_FWPATCH_REVISION	0x0012
#define VD_BOOT			0x0200
#define  BOOT_PATCH_AND_BOOT	2
#define VD_STBY			0x0201
#define VD_STREAMING		0x0202
#define VD_EXT_CLOCK		0x0220
#define VD_EXPOSURE_USE_CASES	0x0312
#define VD_CTX_REPEAT_CTX0	0x03dc
#define VD_NEXT_CTX		0x03e4
#define VD_PATCH		0x2000
/* context 0 */
#define VD_AE_TARGET_PERCENTAGE	0x0486	/* default 27 */
#define VD_EXP_MODE		0x0500
#define  EXP_AUTO		0
#define  EXP_MANUAL		2
#define VD_MANUAL_AGAIN		0x0501
#define VD_MANUAL_EXPOSURE	0x0502
#define VD_FRAME_LENGTH		0x050c
#define VD_GPIO2_CTRL		0x051f
#define  GPIO_IN		1
#define  GPIO_STROBE		2

#define VD_XCLK		12000000	/* the IR camera's own oscillator */

static int vd_write(struct sucam *cam, u16 reg, const void *val, int len)
{
	u8 b[2 + 64];
	int ret;

	b[0] = reg >> 8;
	b[1] = reg & 0xff;
	memcpy(b + 2, val, len);
	ret = i2c_master_send(cam->sensor, b, len + 2);
	return ret == len + 2 ? 0 : (ret < 0 ? ret : -EIO);
}

static int vd_write8(struct sucam *cam, u16 reg, u8 val)
{
	return vd_write(cam, reg, &val, 1);
}

static int vd_write16(struct sucam *cam, u16 reg, u16 val)
{
	u8 b[2];

	put_unaligned_le16(val, b);
	return vd_write(cam, reg, b, 2);
}

static int vd_write32(struct sucam *cam, u16 reg, u32 val)
{
	u8 b[4];

	put_unaligned_le32(val, b);
	return vd_write(cam, reg, b, 4);
}

static int vd_read(struct sucam *cam, u16 reg, u8 *val, int len)
{
	u8 a[2] = { reg >> 8, reg & 0xff };
	struct i2c_msg m[2] = {
		{ .addr = cam->sensor->addr, .len = 2, .buf = a },
		{ .addr = cam->sensor->addr, .flags = I2C_M_RD, .len = len, .buf = val },
	};
	int ret = i2c_transfer(cam->sensor->adapter, m, 2);

	return ret == 2 ? 0 : (ret < 0 ? ret : -EIO);
}

static int vd_read8(struct sucam *cam, u16 reg)
{
	u8 v;

	return vd_read(cam, reg, &v, 1) ?: v;
}

static int vd_wait(struct sucam *cam, u16 reg, u8 want)
{
	int v;

	return read_poll_timeout(vd_read8, v, v == want, 2000, 500000, false, cam, reg);
}

/* the in-tree vd55g1 driver's exposure bias: AE target 27 % * 2^EV */
const s64 sucam_ir_ev_bias[13] = {
	-3000, -2500, -2000, -1500, -1000, -500, 0, 500, 1000, 1500, 2000, 2500, 3000,
};
const u8 sucam_ir_ae_target[13] = { 3, 5, 7, 10, 14, 19, 27, 38, 54, 76, 108, 153, 216 };

int sucam_vd_set(struct sucam *cam, u32 id, s32 val)
{
	if (!cam->powered)
		return 0;	/* applied at next stream start */
	switch (id) {
	case V4L2_CID_EXPOSURE_AUTO:
		return vd_write8(cam, VD_EXP_MODE, val == V4L2_EXPOSURE_AUTO ? EXP_AUTO : EXP_MANUAL);
	case V4L2_CID_AUTO_EXPOSURE_BIAS:	/* AE target 27 % * 2^EV, as in vd55g1.c */
		return vd_write8(cam, VD_AE_TARGET_PERCENTAGE, sucam_ir_ae_target[val]);
	case V4L2_CID_EXPOSURE:		/* lines, used in manual mode */
		return vd_write16(cam, VD_MANUAL_EXPOSURE, val);
	case V4L2_CID_ANALOGUE_GAIN:	/* gain = 32 / (32 - val) */
		return vd_write8(cam, VD_MANUAL_AGAIN, val);
	case V4L2_CID_FLASH_LED_MODE:	/* IR LED: strobed with the exposure, or off */
		return vd_write8(cam, VD_GPIO2_CTRL,
				 val == V4L2_FLASH_LED_MODE_NONE ? GPIO_IN : GPIO_STROBE);
	case V4L2_CID_HBLANK:		/* read-only description of the mode */
	case V4L2_CID_VBLANK:
	case V4L2_CID_PIXEL_RATE:
	case V4L2_CID_CAMERA_ORIENTATION:
	case V4L2_CID_CAMERA_SENSOR_ROTATION:
		return 0;
	default:
		return -EINVAL;
	}
}

int sucam_vd_power(struct sucam *cam, bool on)
{
	u8 rev[2];
	int i, ret;

	if (!on) {
		gpiod_set_value_cansleep(cam->gpio[SUCAM_GPIO_PLED], 0);
		gpiod_set_value_cansleep(cam->gpio[SUCAM_GPIO_RESET], 1);
		gpiod_set_value_cansleep(cam->gpio[SUCAM_GPIO_AVDD], 0);
		gpiod_set_value_cansleep(cam->gpio[SUCAM_GPIO_CAMPOWER], 0);
		cam->powered = false;
		return 0;
	}
	gpiod_set_value_cansleep(cam->gpio[SUCAM_GPIO_CAMPOWER], 1);
	gpiod_set_value_cansleep(cam->gpio[SUCAM_GPIO_AVDD], 1);
	/* ACPI lists pled for the IR camera too: indicator, possibly the IR LED enable */
	gpiod_set_value_cansleep(cam->gpio[SUCAM_GPIO_PLED], 1);
	usleep_range(5000, 6000);
	gpiod_set_value_cansleep(cam->gpio[SUCAM_GPIO_RESET], 0);	/* deassert */
	ret = vd_wait(cam, VD_FSM, FSM_READY_TO_BOOT);
	if (ret) {
		dev_err(cam->dev, "VD55G1 not responding\n");
		goto err;
	}
	ret = vd_write32(cam, VD_EXT_CLOCK, VD_XCLK);
	for (i = 0; i < ARRAY_SIZE(vd55g1_patch) && !ret; i += 64)
		ret = vd_write(cam, VD_PATCH + i, vd55g1_patch + i,
			       min_t(int, 64, ARRAY_SIZE(vd55g1_patch) - i));
	ret = ret ?: vd_write8(cam, VD_BOOT, BOOT_PATCH_AND_BOOT);
	ret = ret ?: vd_wait(cam, VD_BOOT, 0);
	ret = ret ?: vd_wait(cam, VD_FSM, FSM_SW_STBY);
	ret = ret ?: vd_read(cam, VD_FWPATCH_REVISION, rev, 2);
	if (ret || rev[1] != VD55G1_PATCH_MAJOR || rev[0] != VD55G1_PATCH_MINOR) {
		dev_err(cam->dev, "VD55G1 firmware patch failed (%d, rev %u.%u)\n",
			ret, rev[1], rev[0]);
		ret = ret ?: -EIO;
		goto err;
	}
	cam->powered = true;
	return 0;
err:
	sucam_vd_power(cam, false);
	return ret;
}

int sucam_vd_stream(struct sucam *cam, bool on)
{
	int i, ret = 0;

	if (!on) {
		vd_write8(cam, VD_STREAMING, 1);
		return vd_wait(cam, VD_FSM, FSM_SW_STBY);
	}
	for (i = 0; i < ARRAY_SIZE(vd55g1_windows) && !ret; i++)
		ret = vd_write8(cam, vd55g1_windows[i].reg, vd55g1_windows[i].val);
	/* one context only, 30 fps (2 x the Windows frame length) */
	ret = ret ?: vd_write8(cam, VD_EXPOSURE_USE_CASES, 0);
	ret = ret ?: vd_write16(cam, VD_NEXT_CTX, 0);
	ret = ret ?: vd_write16(cam, VD_CTX_REPEAT_CTX0, 0);
	ret = ret ?: vd_write32(cam, VD_FRAME_LENGTH, SUCAM_IR_FRAME_LENGTH);
	if (ret)
		return ret;
	ret = v4l2_ctrl_handler_setup(&cam->ctrls);	/* AE / exposure / LED */
	ret = ret ?: vd_write8(cam, VD_STBY, 1);
	ret = ret ?: vd_wait(cam, VD_STBY, 0);
	return ret ?: vd_wait(cam, VD_FSM, FSM_STREAMING);
}
