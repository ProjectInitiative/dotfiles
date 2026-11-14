/* SPDX-License-Identifier: GPL-2.0 */
/*
 * Surface Laptop Ultra cameras (MediaTek ISP8 seninf -> camsv):
 *   front: OV02C10, CSI port 0, 2 lanes
 *   IR:    VD55G1,  CSI port 2, 1 lane
 * Both use outmux1 -> camsv_b, so only one of them can stream at a time.
 */
#ifndef SUCAM_DRV_H
#define SUCAM_DRV_H

#include <linux/gpio/consumer.h>
#include <linux/i2c.h>
#include <linux/kthread.h>
#include <linux/list.h>
#include <linux/mutex.h>
#include <linux/spinlock.h>
#include <linux/workqueue.h>
#include <media/media-device.h>
#include <media/v4l2-ctrls.h>
#include <media/v4l2-device.h>
#include <media/v4l2-subdev.h>
#include <media/videobuf2-v4l2.h>

/*
 * camsv grabs all 1928 columns of the sensor's 2-lane mode and its top 1080
 * lines. The full width matters: libcamera's software ISP gives up 2 columns
 * on each side to demosaic, so from 1920 it could only offer 1916x1080, and
 * PipeWire then listed nothing above 1680x1050 (no 1080p for browsers).
 * 1928 * 2 * 1080 = 4164480 bytes, still under the 4 MiB DMA limit.
 */
#define SUCAM_W		1928
#define SUCAM_H		1080
#define SUCAM_FPS	30
/* the sensor's full 2-lane mode */
#define SUCAM_SENSOR_W	1928
#define SUCAM_SENSOR_H	1092

/* camsv_b interrupts in ISP1 _CRS: 0x20A = done/err, 0x20D = SOF (tag n at bit 2+4n) */
#define SUCAM_SOF_GSI	0x20D

/* camsv_b FORMAT_TAG2 (+0x594): pixel depth in the low field (0 RAW8, 1 RAW10),
 * bit 6 = unpacked into 16-bit words (docs/camsv-output-format.md) */
#define SUCAM_SV_RAW8		0x00
#define SUCAM_SV_RAW10		0x01
#define SUCAM_SV_UNPACKED	BIT(6)

/*
 * OV02C10 2-lane 1928x1092 mode. The stock table (HTS 1140, VTS 2328) assumes a
 * 19.2 MHz MCLK and runs at 18.8 fps here (line time 22.8 us, i.e. the board
 * oscillator is ~12 MHz), so the frame length is shortened to get 30 fps.
 */
#define SUCAM_VTS		1462
#define SUCAM_VTS_MAX		0x7fff
#define SUCAM_EXP_MIN		4
#define SUCAM_EXP_MAX		(SUCAM_VTS - 8)
/*
 * Line length for frame timing (libcamera: frame = (W + HBLANK) * (H + VBLANK)
 * / PIXEL_RATE). The sensor is programmed in lines only; a 2280-pixel line
 * (2 x HTS) with the rate below gives 30 fps at VTS 1462, as measured.
 */
#define SUCAM_LLP		2280
#define SUCAM_PIXEL_RATE	((u64)SUCAM_LLP * SUCAM_VTS * SUCAM_FPS)
#define SUCAM_EXP_DEF		1132
#define SUCAM_AGAIN_MIN		0x10
#define SUCAM_AGAIN_MAX		0xf8
#define SUCAM_AGAIN_DEF		0x80
#define SUCAM_DGAIN_MIN		0x400
#define SUCAM_DGAIN_MAX		0x3fff
#define SUCAM_DGAIN_DEF		0x400

/*
 * IR camera: 600x600 mono RAW10 out of the sensor (Windows' crop of 804x704).
 *
 * camsv grabs 592 of the sensor's 600 columns (4 off each side) so that a line
 * of 8-bit grey is exactly 16-byte aligned: with padding (600 in 608 bytes)
 * ffmpeg's V4L2 input drops every frame as the wrong size.
 */
#define SUCAM_IR_GRAB_X		4
#define SUCAM_IR_W		592
#define SUCAM_IR_H		600
#define SUCAM_IR_FRAME_LENGTH	4010		/* lines: 30 fps at 1086 Mbps */
/*
 * The IR image is lit by the illuminator, which the sensor strobes for the
 * exposure time; its driver stops the pulse somewhere between 2800 and 3300
 * lines (black frames). The sensor's own AE runs the exposure up to the frame
 * length, so default to a fixed exposure in the lit range.
 */
#define SUCAM_IR_EXP_MAX	2500
#define SUCAM_IR_EXP_DEF	2000
#define SUCAM_IR_AGAIN_MAX	28		/* gain = 32 / (32 - val) */
#define SUCAM_IR_AGAIN_DEF	16		/* 2x: the face at arm's length, ~48 of 255 */
#define SUCAM_IR_SENSOR_W	804
#define SUCAM_IR_SENSOR_H	704
/* frame timing for libcamera, as for the front camera (lines are what count) */
#define SUCAM_IR_LLP		1000
#define SUCAM_IR_PIXEL_RATE	((u64)SUCAM_IR_LLP * SUCAM_IR_FRAME_LENGTH * SUCAM_FPS)

struct sucam_fmt {
	u32 fourcc, stride, sv_fmt;
	const char *desc;
};

struct sucam_cfg {
	bool ir;
	const char *card;		/* V4L2 card name */
	const char *input;
	u32 width, height;
	const struct sucam_fmt *fmts;	/* fmts[0] is the default */
	unsigned int nfmts;
	/* media graph: sensor subdev */
	const char *sensor;		/* driver name of the sensor (libcamera's model) */
	u32 mbus;
	struct v4l2_rect native, crop;	/* sensor array and the part camsv grabs */
};

extern const struct sucam_cfg sucam_front_cfg, sucam_ir_cfg;

enum { SUCAM_GPIO_CAMPOWER, SUCAM_GPIO_AVDD, SUCAM_GPIO_MCLK, SUCAM_GPIO_RESET,
       SUCAM_GPIO_PLED, SUCAM_GPIO_NUM };

struct sucam_buf {
	struct vb2_v4l2_buffer vb;
	struct list_head list;
};

struct sucam {
	struct device *dev;
	const struct sucam_cfg *cfg;
	const struct sucam_fmt *fmt;	/* current capture format */
	struct v4l2_device v4l2_dev;
	struct video_device vdev;
	struct vb2_queue queue;
	struct v4l2_ctrl_handler ctrls;
	struct v4l2_ctrl *exposure, *again, *dgain;
	u32 vts;			/* front sensor frame length, lines */

	/* front camera media graph: sensor -> seninf -> video node */
	struct media_device mdev;
	struct media_pad vpad;
	struct v4l2_subdev sensor_sd, seninf_sd;
	struct media_pad sensor_pad, seninf_pads[2];
	struct mutex lock;		/* vdev / vb2 / hw state */

	/* hw */
	void __iomem *hfrp, *ccu, *sv;
	struct i2c_client *sensor;
	struct device *sensor_dev;
	struct gpio_desc *gpio[SUCAM_GPIO_NUM];
	bool powered, streaming;

	/* buffer flow (camsv FBC, driven by the camsv_b SOF interrupt) */
	spinlock_t qlock;
	struct list_head queued;	/* waiting to be armed */
	struct sucam_buf *pending;	/* in the outer WDMA addr, latched at next SOF */
	struct sucam_buf *writing;	/* latched by the last SOF, being written */
	int irq;			/* SOF interrupt, < 0 if unavailable */
	bool irq_on;			/* requested for the current stream */
	struct task_struct *poll;	/* fallback when there is no interrupt */
	struct delayed_work watchdog;	/* logs hardware state while frames stall */
	u32 watch_seq;
	u8 last_wcnt;
	u32 sequence;
	u32 dropped;		/* frames lost at SOF (buffer requeued) */
};

int sucam_hw_init(struct sucam *cam);
void sucam_hw_exit(struct sucam *cam);
int sucam_hw_start(struct sucam *cam, dma_addr_t first);
void sucam_hw_stop(struct sucam *cam);
void sucam_hw_arm(struct sucam *cam, dma_addr_t addr);
u8 sucam_hw_wcnt(struct sucam *cam);
void sucam_hw_power_lost(void);
bool sucam_hw_sof(struct sucam *cam);
void sucam_hw_diag(struct sucam *cam);
void sucam_hw_stream_result(struct sucam *cam, u32 frames);
int sucam_sensor_set(struct sucam *cam, u32 id, s32 val);

/* sucam_mc.c */
int sucam_mc_init(struct sucam *cam);
int sucam_mc_register(struct sucam *cam);
void sucam_mc_unregister(struct sucam *cam);

/* sucam_vd55g1.c */
extern const s64 sucam_ir_ev_bias[13];		/* milli-EV, -3 .. +3 in half steps */
extern const u8 sucam_ir_ae_target[13];		/* matching AE target percentages */
int sucam_vd_power(struct sucam *cam, bool on);
int sucam_vd_stream(struct sucam *cam, bool on);
int sucam_vd_set(struct sucam *cam, u32 id, s32 val);

#endif
