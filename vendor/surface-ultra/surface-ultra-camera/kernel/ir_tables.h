/* SPDX-License-Identifier: GPL-2.0 */
/*
 * IR camera (ST VD55G1, 1 data lane) receive path: CSI port 2 (PHY2 @ 0x12a20000) ->
 * mac_csi2 -> async 2 -> outmux1 -> camsv_b, shared with the front camera's outmux/camsv.
 * Derived from the front camera's Windows capture (ccu_replay.h, golden_mmio.h): no Windows
 * capture of the IR camera exists. Tags: [H] high [M] medium [L] guess [=] same as port 0.
 * Verified on hardware: everything needed for 600x600 RAW10 frames to reach memory,
 * including MIPI_SPLIT 1 in set_async. outmux0/camsv_a do not work for this path.
 */

/* ---- direct MMIO ---- */
/*
 * DRAFT (untested): direct-MMIO state for the IR camera receive path
 *   VD55G1 (1 lane D-PHY, RAW10 = DT 0x2b like Windows) -> PHY2 -> mac_csi2 -> async 2
 *   -> outmux0 (tag 1) -> camsv_a (TAG2 / WDMA IMG2)
 * derived from kernel/golden_mmio.h + golden_omux_all.h (front camera, port 0).
 * Register meanings: mtkcam/camsys/isp8/cam/mtk_csi_phy_3_0/ headers. See port2-derivation.md.
 *
 * Tags: [H] high [M] medium [L] guess [=] copied unchanged from the port-0 golden state.
 * Every value not listed in the "changed" comments is the Windows port-0 value.
 */
#define P2_RXANA_A	0x12a20000	/* CCU only (cmd 0xa0) */
#define P2_RXANA_B	0x12a21000	/* CCU only */
#define P2_DPHY		0x12a22000	/* [H] ACPI SENI MEMS: dphy[2] */
#define P2_MAC_TOP	0x12a24000	/* [H] mac-top[2] */
#define P2_MAC_CSI	0x12a25000	/* [H] mac-csia[2] */
/* = 0x12a20000 + 0x2000 / 0x4000 / 0x5000: phy_mac_setup() works unchanged with
 * SENINF_MMIO = 0x12a20000 once the tables below are used. */

/* VD55G1 frame as configured by the Windows driver (surfacemipicamsensor.sys mode table):
 * 600x600 crop at (102, 52) of 804x704, RAW10. Change both if another mode is used. */
#define P2_W		600
#define P2_H		600
#define P2_DT		0x2b		/* RAW10 (Y10). RAW8 would be 0x2a, see notes */


static const struct rw ir_dphy[] = {
	{ 0x0000, 0x00000101 },	/* changed [H] DPHY_RX_LANE_EN: LC0_EN, LD0_EN (port0 2-lane: 0x301) */
	{ 0x0004, 0x80000002 },	/* changed [M] LANE_SELECT: CK_DATA_MUX_EN, LC0_SEL=2 (A lane 2 = clock),
				 * LD0_SEL=0 (A lane 0) - N1X map (port0: 0x80001002 = LD1_SEL 1).
				 * Alternatives in order: 0x80001002 (keep port0 value, LD1 disabled anyway),
				 * 0x80000102 (LD0=A1, MTK mt6991 map), 0x80000302 (LD0=B0), 0x80000402 (LD0=B1).
				 * The clock lane cannot really move: which analog lane runs in clock mode
				 * is set in rxana ANA_0, which only the CCU firmware writes. */
	{ 0x0010, 0x10000000 },	/* [=] CLOCK_LANE0: PREPARE_EN, settle_ck 0 */
	{ 0x0014, 0x10000000 },	/* [=] CLOCK_LANE1 */
	{ 0x0020, 0x10680000 },	/* [=] DATA_LANE0: PREPARE_EN, HS_SETTLE 0x1a (26 -> 32 cycles @312 MHz = 103 ns) */
	{ 0x0024, 0x10680000 },	/* [=] (unused lanes, harmless) */
	{ 0x0028, 0x10680000 },
	{ 0x002c, 0x10680000 },
	{ 0x0040, 0x0000001d },	/* [=] SYNC_DETECT_* patterns */
	{ 0x0044, 0x000000ff },
	{ 0x0048, 0x000000f0 },
	{ 0x004c, 0x0000ff1d },
	{ 0x0050, 0x7f000d00 },	/* [=] DESKEW_CTRL (init deskew only used > 1.5 Gbps) */
	{ 0x0054, 0x03020016 },
	{ 0x0058, 0x020000e4 },
	{ 0x0060, 0x00700000 },
	{ 0x0064, 0x00700000 },
	{ 0x0068, 0x00700000 },
	{ 0x006c, 0x00700000 },
	{ 0x0094, 0xc0000001 },	/* [=] DPHY_RX_IRQ_EN (ERR_SOT_SYNC_HS_L0 + bits 30/31) */
	{ 0x00f0, 0x000000f1 },	/* [=] SPARE0 */
	{ 0x00f4, 0x000000f0 },
	{ 0x0110, 0x00005f00 },	/* [=] BIST config (reset values on Windows) */
	{ 0x0118, 0x00040387 },
	{ 0x011c, 0x00000704 },
	{ 0x0120, 0x00007d00 },
	{ 0x0128, 0x00040387 },
	{ 0x012c, 0x00000704 },
	{ 0x0130, 0x0000af00 },
	{ 0x0138, 0x00040387 },
	{ 0x013c, 0x00000704 },
	{ 0x0140, 0x0000be00 },
	{ 0x0148, 0x00040387 },
	{ 0x014c, 0x00000704 },
	{ 0x0180, 0x200f0f08 },	/* [=] DPHYV21_CTRL (SYNC_METH_SEL=1) */
	{ 0x0184, 0x00000001 },	/* [=] written separately in phy_mac_setup() */
	{ 0x0188, 0x01050701 },	/* [=] HS_IDLE_CNT */
};

static const struct rw ir_mactop[] = {
	/* +0x04 is RO_MAC_VERSION_CODE (in golden_mmio.h only because it was dumped) */
	{ 0x0040, 0x00000001 },	/* [=] PHY_CTRL_CSI0: DPHY_EN */
};

static const struct rw ir_maccsi[] = {
	/* +0x00 CSI2_EN goes LAST (see below) */
	{ 0x0004, 0x001d04b6 },	/* [=] OPT (ECC/B2P/IMG_PKT/V2P0/MULTI_FRAME, VS_1T, 8_16_PIXEL_SEL,
				 * EXTDT+RAW8 PIXEL_DOUBLE, EARLY_VSYNC) */
	{ 0x0010, 0x0000011f },	/* [=] RESYNC_MERGE_CTRL */
	{ 0x0014, 0x00308408 },	/* [=] RESYNC_MERGE_CTRL2 (written separately in phy_mac_setup()) */
	{ 0x0020, (P2_DT << 16) | 0x11 },	/* [H] S0_DI_CTRL: DT_SEL, VC 0, DT/VC interleave (port0 0x002b0011) */
	{ 0x0044, 0x00050001 },	/* [=] BIT_ERR_CTRL: CNT_EN, threshold 5 */
	{ 0x0080, 0x00010810 },	/* [=] descramble seeds (defaults) */
	{ 0x0084, 0x10081818 },
	{ 0x0090, 0x01800990 },
	{ 0x0094, 0x11881998 },
	{ 0x00a0, 0x02400a51 },
	{ 0x00a4, 0x12481a59 },
	{ 0x00b0, 0x03c00bd0 },
	{ 0x00b4, 0x13c81bd8 },
	{ 0x00c0, 0x80000000 },	/* [=] IRQ_EN (CLR_MODE). For debugging 0xbf0023ff (errors+FS/FE/LS/LE), see notes */
	{ 0x00e0, 0x00020000 },	/* [=] DBG_CTRL: PACKET_CNT_EN */
	{ 0x0100, 0x00000127 },	/* [=] R24USERDEF_DT 0x27 */
	{ 0x0104, 0x2e2d2c2b },	/* [=] DT0: RAW10/12/14/16 */
	{ 0x0108, 0x1f1d192f },	/* [=] DT1 */
	{ 0x010c, 0x26002422 },	/* [=] DT2 */
	{ 0x0118, 0x12121212 },	/* [=] FORCEDT2 */
	/* (0x50/0x54 in golden_mmio.h are RO BIT_ERR_MIN_CYCLE readings; not needed) */
};
#define P2_CSI2_EN	0x00000001	/* changed [H] LANE0_EN only (port0 2-lane: 0x3) */

/*
 * outmux0 (0x3A100000) for the IR stream. Written on top of g_omux_all (which parks
 * outmux0 at SRC_SEL/SOURCE_CONFIG_0 = 3), then SW_CFG_DONE (+0x1c) = 1.
 * Choice: outmux N feeds camsv instance N (camsv_a=0, camsv_b=1, camsv_e=4 in the ISP1
 * _DSM; front = outmux1 -> camsv_b); 0/1/4 are the only non-waived camsv outmuxes
 * (SENI OMUX second field = waived flag).                                          [M]
 * Alternative: outmux4 (0x3A140000) -> camsv_e (0x3A540000), same values.
 */
#define P2_OUTMUX	0x3a100000
static const struct rw ir_omux[] = {
	{ 0x0004, 0x00000002 },	/* [=] FILT_MODE */
	{ 0x0008, 0x00000000 },	/* [=] PIX_MODE */
	{ 0x000c, 0x00000020 },	/* changed [M] SOURCE_CONFIG_0: VSYNC_SRC_SEL_MIPI=async 2, SEN 0, REF/LAST VC 0
				 * (front: 0 = async 0). Alt: 0x00000000 if the fw match uses SEN only. */
	{ 0x0010, 0x00000000 },	/* [=] TAG_VC_0..3 = 0 */
	{ 0x0014, 0x00000000 },
	{ 0x0018, 0x00000020 },	/* changed [M] SRC_SEL: MIPI=2, SEN=0 (SEN<2 = "route me" for the CCU fw) */
	{ 0x0020, 0x01000001 },	/* [=] CSR_CFG_CTRL */
	{ 0x0024, 0x00000001 },	/* [=] */
	{ 0x002c, 0x00000001 },	/* [=] CAM_CFG_RDY */
	{ 0x0040, 0x0202021f },	/* [=] IRQ_EN */
	{ 0x0098, 0x0000ffff },	/* [=] TAG_CRC_PORT_0 */
	{ 0x009c, (P2_DT << 16) | 0x1 },	/* [H] TAG_VCDT_FILT_1: DT, VC 0, FILT_EN (front 0x002b0001) */
	{ 0x00a0, ((P2_H - 1) << 16) | (P2_W - 1) },	/* [H] TAG_SIZE_1 = 0x02570257 for 600x600 */
	{ 0x00b4, 0x0000ffff },	/* [=] CRC ports */
	{ 0x00d0, 0x0000ffff },
	{ 0x00ec, 0x0000ffff },
	{ 0x0108, 0x0000ffff },
	{ 0x0124, 0x0000ffff },
	{ 0x0140, 0x0000ffff },
	{ 0x015c, 0x0000ffff },
};

/*
 * camsv_a (0x3A500000, DMA block +0x1000). Same register layout as camsv_b, so
 * g_camsv1 / g_camsv1dma from golden_mmio.h are reused with these overrides.
 * Clocks: 0xa04 0xa01(clarb14) 0xa0b 0xa10-0xa13 0xa17(camsv_a)   (camsv_b needed 0xa00 0xa18)
 * IRQ (ISP1 _CRS): done/err GSI 521 (0x209), SOF GSI 524 (0x20C).  camsv_e: 0x20B / 0x20E,
 *   clocks 0xa03(clarb29) 0xa1b.
 * SMI: CAM_MAIN(0x3A000000)+0x590 LARB13_VC_SEL=0x67 was needed for camsv_b; for camsv_a the
 *   LARB14 register is probably +0x594, value unknown (0x37 was an earlier guess)      [L]
 */
#define P2_CAMSV	0x3a500000
static const struct rw ir_camsv_override[] = {
	/* [H] GRAB_PXL_TAG2 = end << 16 | start (Windows: 0x02580000, front 0x07800000) */
	{ 0x0588, (SUCAM_IR_GRAB_X + SUCAM_IR_W) << 16 | SUCAM_IR_GRAB_X },
	{ 0x058c, P2_H << 16 },	/* [H] GRAB_LIN_TAG2 = 0x02580000 (front 0x04380000) */
	/* +0x594 FORMAT_TAG2 = 1 (RAW10) unchanged [M]; RAW8 code unknown (probably 0) */
};
/* WDMA_BASIC_IMG2 (+0x1250) = (stride << 16) | 0x10. 600 px RAW10 = 750 bytes.
 * stride 752 (16-byte aligned) first, then 768, 800.                                   [M] */
#define P2_STRIDE	752

/* ---- CCU stream-on sequence ---- */
/*
 * DRAFT (untested): CCU mailbox stream-on sequence for the IR camera
 * (ST VD55G1, 1 data lane, CSI port 2 = PHY2 @ 0x12A20000, async 2),
 * derived from kernel/ccu_replay.h (front OV02C10, port 0, 2 lanes, async 0).
 * Derivation and reasoning: port2-derivation.md (Japanese).
 *
 * Confidence tags:  [H] high  [M] medium  [L] low/guess  [=] unchanged, port-independent
 * Payloads are little-endian u32 words written as bytes (same format as ccu_replay.h).
 *
 * Use as: entries [0, IR_SS) before the PHY/mac MMIO + sensor stream-on,
 *         entries [IR_SS, end) after the sensor streams (like hw_start_once()).
 *
 * If the front camera is ALREADY streaming, skip the "first-user only" entries
 * (common_reg_setup + disable_all_outmux, marked FU): Windows only sends them when
 * the seninf power refcount goes 0->1, and the 0x84 list would gate off the front
 * camera's outmux 1/7 clocks.
 */

#define W(x) (x) & 0xff, ((x) >> 8) & 0xff, ((x) >> 16) & 0xff, ((x) >> 24) & 0xff

/* port-2 constants */
#define IR_PORTNUM	2		/* CSI_PORT_2 (4D1C), ACPI CAMI HWIF csiport 2   [H] */
#define IR_ASYNC	2		/* ACPI SENI CSIA: (port 2, async 2, top 0)      [H] */
#define IR_SENSOR_ID	2		/* INF: SensorIndex 2 (front = 1)                [H] */
#define IR_SENSOR_TYPE	2		/* INF: SensorType 2 = IR (front = 0)            [H] */
#define IR_OUTMUX	1		/* outmux1 -> camsv_b, as the front camera (outmux0/camsv_a never latch) */
#define RXA		0x12a20000	/* rxana csia, PHY2                              [H] */
#define RXB		0x12a21000	/* rxana csib, PHY2                              [H] */
/*
 * CSI efuse of port 2 (SMC 0xC2000515 x2=0x38). Unknown; port 0's value is used.
 * 0x84210805 decodes to HSRT codes 16,16,16 (A) / 16,16,1 (B) = almost the
 * nominal 0x10 that cmd 0xa1 already writes.                                    [L]
 * Alternatives: (1) drop the two 0xa2 entries (HSRT stays 0x10);
 *               (2) read port 2's efuse from Linux with the same SMC as Windows.
 */
#define IR_EFUSE	0x84210805

static const struct ccucmd ir_replay[] = {
	/* ---- ft1 sysctrl / ft2 camsysctrl prologue, sent before every Windows stream-on.
	 * Meaning unknown. ft2 cmd2 {1,0,3,0}: word0 might be the sensor index (try 2) [L] */
	{ 1, 0xd, 0, {  } },						/* [=] */
	{ 2, 0x2, 16, { W(IR_SENSOR_ID), W(0), W(3), W(0) } },			/* [L] alt {2,0,3,0} */
	{ 1, 0xf, 0, {  } },						/* [=] */
	{ 2, 0x4, 8, { W(0x12), W(0) } },				/* [=] */

	/* ---- MSG_SENINF set_iomem {iomv idx 1=mt8991, outmux_num 14, async_count 6,
	 * seninf-top, async, TG[0..5]}. Port-independent. */
	{ 4, 0x0, 44, { W(1), W(14), W(6), W(0x3a300000), W(0x3a301000),
			W(0x3a302000), W(0x3a302200), W(0x3a302400), W(0x3a302600),
			W(0x3a302800), W(0x3a302a00) } },			/* [=] */

	/* ---- common_reg_setup (FU) */
	{ 4, 0x86, 4, { W(1) } },		/* FU [=] TOP_CTRL.SW_CFG_LEVEL=1 */
	{ 4, 0x82, 4, { W(0xffffffff) } },	/* FU [=] ASYNC_CG_EN (fw writes 0x3f) */
	{ 4, 0x85, 4, { W(0xffffffff) } },	/* FU [=] OUTMUX_CG_EN (fw writes 0x7fffff) */
	{ 4, 0x87, 4, { W(0xffffffff) } },	/* FU [=] ASYNC_OVERRUN_IRQ_EN */

	/* ---- set_phya_clock_src: rxanaA(port)+0xf0 CSR_ANA_REF_CK_SEL=1 (osc) */
	{ 4, 0xa0, 12, { W(RXA + 0xf0), W(0x8), W(0x8) } },		/* [H] */

	/* ---- disable_all_outmux (FU): 0x84 = clear OUTMUX_CG bit, all non-waived outmuxes.
	 * If the front camera streams, send only { 4, 0x84, 4, { W(IR_OUTMUX) } } here. */
	{ 4, 0x84, 4, { W(0) } },	/* FU */
	{ 4, 0x84, 4, { W(1) } },	/* FU */
	{ 4, 0x84, 4, { W(4) } },	/* FU */
	{ 4, 0x84, 4, { W(6) } },	/* FU */
	{ 4, 0x84, 4, { W(7) } },	/* FU */
	{ 4, 0x84, 4, { W(9) } },	/* FU */
	{ 4, 0x84, 4, { W(11) } },	/* FU */
	{ 4, 0x84, 4, { W(13) } },	/* FU */

	/* ---- csirx_phyA_init, A half (4D1C: both A and B are initialised even for 1 lane) */
	{ 4, 0xa0, 12, { W(RXA + 0x04), W(0x00070077), W(0x00020044) } },	/* [H] ANA_1 LPRX VTL/VTH=4, EQ_DES_VREF=2 */
	{ 4, 0xa0, 12, { W(RXA + 0x14), W(0x0000ff7f), W(0x00000045) } },	/* [H] ANA_5 EQ BW/IS/LATCH=1 */
	{ 4, 0xa0, 12, { W(RXA + 0x38), W(0x00000100), W(0x00000100) } },	/* [H] ANA_14 EQ_OS_IS=1 */
	{ 4, 0xa0, 12, { W(RXA + 0x18), W(0x3f3f3f3f), W(0x04090909) } },	/* [H] ANA_6 (C-PHY CDR, harmless) */
	{ 4, 0xa0, 12, { W(RXA + 0x1c), W(0x3f3f3f3f), W(0x04090909) } },	/* [H] ANA_7 */
	{ 4, 0xa0, 12, { W(RXA + 0x20), W(0x0000ffff), W(0x00000400) } },	/* [H] ANA_8 RESERVE=0x400 */
	{ 4, 0xa1, 8, { W(IR_PORTNUM), W(0) } },	/* [H] phyA_init tail {portNum, A}: HSRT=0x10 etc. */
	/* ---- B half */
	{ 4, 0xa0, 12, { W(RXB + 0x04), W(0x00070077), W(0x00020044) } },	/* [H] */
	{ 4, 0xa0, 12, { W(RXB + 0x14), W(0x0000ff7f), W(0x00000045) } },	/* [H] */
	{ 4, 0xa0, 12, { W(RXB + 0x38), W(0x00000100), W(0x00000100) } },	/* [H] */
	{ 4, 0xa0, 12, { W(RXB + 0x18), W(0x3f3f3f3f), W(0x04090909) } },	/* [H] */
	{ 4, 0xa0, 12, { W(RXB + 0x1c), W(0x3f3f3f3f), W(0x04090909) } },	/* [H] */
	{ 4, 0xa0, 12, { W(RXB + 0x20), W(0x0000ffff), W(0x00000400) } },	/* [H] */
	{ 4, 0xa1, 8, { W(IR_PORTNUM), W(1) } },	/* [H] {portNum, B} */

	/* ---- apply_efuse_data {portNum, A/B, efuse} */
	{ 4, 0xa2, 12, { W(IR_PORTNUM), W(0), W(IR_EFUSE) } },	/* [L] see IR_EFUSE */
	{ 4, 0xa2, 12, { W(IR_PORTNUM), W(1), W(IR_EFUSE) } },	/* [L] */

	/* ---- async: CG on + set_async {async, split=!4d1c=0, test model 0, debug_en 1} */
	{ 4, 0x80, 4, { W(IR_ASYNC) } },				/* [H] */
	{ 4, 0x89, 16, { W(IR_ASYNC), W(1), W(0), W(1) } },		/* MIPI_SPLIT 1: a 1-lane sensor is the A half of the 4D1C port (verified; split 0 delivers nothing) */
	/*
	 * 0x87 after set_async. The front capture shows {0x12a100f4} (8x) or {0} (7x):
	 * a torn read of the mailbox (payload of the neighbouring command). The front
	 * replay sends 0x12a100f4 and works. Keep it; alternatives {0}, {0xffffffff}.  [L]
	 */
	{ 4, 0x87, 4, { W(0x12a100f4) } },

	/* ---- csirx_phyA_setting (D-PHY) */
	/*
	 * ANA_SETTING_1 (baseA only). 2 lanes 4D1C: 0x40630044 (DUMMY_VALID_NUM 6, SPLIT_EN 0).
	 * 1 lane: MTK and nvSeninf use DUMMY_VALID_NUM 9, SPLIT_EN 1 -> 0x4093004c.     [M]
	 * Alt: 0x40630044 (front value), then 0x40930044.
	 */
	{ 4, 0xa0, 12, { W(RXA + 0xf4), W(0x7fff00fc), W(0x4093004c) } },
	{ 4, 0xa0, 12, { W(RXA + 0xf0), W(0x100000f0), W(0x00000020) } },	/* [H] ASYNC_FIFO_GATING_SEL=2 */
	{ 4, 0xa0, 12, { W(RXA + 0x38), W(0x03000000), W(0x01000000) } },	/* [H] LDO_LP_EN=1, X26M=0 */
	{ 4, 0xa0, 12, { W(RXB + 0x38), W(0x03000000), W(0x01000000) } },	/* [H] */
	/* csirx_phyA_dphy_setting(A): 16-bit AFIFO (rate <= 4.5 Gbps), ANA_3 16BIT_SEL, EQ gear 7 */
	{ 4, 0xa0, 12, { W(RXA + 0x100), W(0x00202020), W(0x00202020) } },	/* [H] L0/L1/L2_AFIFO_16BIT_EN */
	{ 4, 0xa3, 16, { W(IR_PORTNUM), W(1), W(0), W(1) } },		/* [H] {portNum, en16, isB, ?=1} */
	{ 4, 0xa0, 12, { W(RXA + 0x14), W(0x0000ffbf), W(0x00001339) } },	/* [H] ANA_5 EQ gear 7 (EQGL[2]=7) */
	{ 4, 0xa0, 12, { W(RXA + 0x38), W(0x00000100), W(0x00000100) } },	/* [H] EQ_OS_IS */
	/* (B) */
	{ 4, 0xa0, 12, { W(RXB + 0x100), W(0x00202020), W(0x00202020) } },	/* [H] */
	{ 4, 0xa3, 16, { W(IR_PORTNUM), W(1), W(1), W(1) } },		/* [H] */
	{ 4, 0xa0, 12, { W(RXB + 0x14), W(0x0000ffbf), W(0x00001339) } },	/* [H] */
	{ 4, 0xa0, 12, { W(RXB + 0x38), W(0x00000100), W(0x00000100) } },	/* [H] */

	/* ---- csirx_phyA_power_on(A): OS_CAL_EN off, BG_CORE/LPF/OS_CAL_RSTB sequence, OS_CAL_EN on.
	 * 0xa4 = {portNum, isB, op (0 core,1 lpf,2 os_cal_rstb), val}. The front replay has torn
	 * payloads for the op=2 step ({0,0x3f0000,0x3f0000,1}); the clean Windows value is used here.
	 * If the port-0 behaviour must be mirrored exactly, send the torn variant instead.  [M] */
	{ 4, 0xa0, 12, { W(RXA + 0x20), W(0x003f0000), W(0) } },		/* [H] */
	{ 4, 0xa4, 16, { W(IR_PORTNUM), W(0), W(0), W(0) } },		/* [H] all off; host waits 200 us */
	{ 4, 0xa4, 16, { W(IR_PORTNUM), W(0), W(0), W(1) } },		/* [H] BG_CORE_EN; 30 us */
	{ 4, 0xa4, 16, { W(IR_PORTNUM), W(0), W(1), W(1) } },		/* [H] BG_LPF_EN; 5 us */
	{ 4, 0xa4, 16, { W(IR_PORTNUM), W(0), W(2), W(1) } },		/* [M] OS_CAL_RSTB; 1 us */
	{ 4, 0xa0, 12, { W(RXA + 0x20), W(0x003f0000), W(0x003f0000) } },	/* [H] OS_CAL_EN x6 */
	/* (B) */
	{ 4, 0xa0, 12, { W(RXB + 0x20), W(0x003f0000), W(0) } },		/* [H] */
	{ 4, 0xa4, 16, { W(IR_PORTNUM), W(1), W(0), W(0) } },		/* [H] */
	{ 4, 0xa4, 16, { W(IR_PORTNUM), W(1), W(0), W(1) } },		/* [H] */
	{ 4, 0xa4, 16, { W(IR_PORTNUM), W(1), W(1), W(1) } },		/* [H] */
	{ 4, 0xa4, 16, { W(IR_PORTNUM), W(1), W(2), W(1) } },		/* [M] */
	{ 4, 0xa0, 12, { W(RXB + 0x20), W(0x003f0000), W(0x003f0000) } },	/* [H] */

	/* ===== IR_SS: here the host writes D-PHY/mac (golden_port2.h), the outmux and camsv,
	 * and starts the VD55G1 (MIPI clock running) before sending the rest. ===== */

	/* MSG_SENINF_SET_SENSOR {sensor_id, sensor_type, 0, csi_port, sel_mipi(async), 0}.
	 * Front: {1,0,0,0,0,0} = INF SensorIndex 1 / SensorType 0 / CsiPort 0 / async 0.
	 * IR from the same INF: SensorIndex 2, SensorType 2, CsiPort 2; async 2 from CSIA.  [H]
	 * The firmware routes every non-waived, CG-enabled outmux whose SRC_SEL[1:0] < 2
	 * and whose (csi_port, sel_mipi) path matches -> outmux0 must be programmed with
	 * SRC_SEL_MIPI = 2 before this (golden_port2.h). Alt ids if 2 is rejected: 1 (only
	 * with the front camera unused, right after a CCU boot), 0.                       */
	{ 4, 0x1, 24, { W(IR_SENSOR_ID), W(IR_SENSOR_TYPE), W(0), W(IR_PORTNUM), W(IR_ASYNC), W(0) } },
	/* outmux clock gate on for the IR outmux (front: {7} raw, {1} camsv).            [M] */
	{ 4, 0x83, 4, { W(IR_OUTMUX) } },
	{ 4, 0x91, 4, { W(0) } },		/* [=] GET_OUTMUX_CG_ENABLE (reply = CG mask, debug only) */
	/* MSG_SENINF_SET_STREAM {sensor_id, on}                                           [H] */
	{ 4, 0x2, 8, { W(IR_SENSOR_ID), W(1) } },
};
#define IR_SS 61	/* index of the SET_SENSOR entry above */

/* stream off: { 4, 0x84, 4, { W(IR_OUTMUX) } }, { 4, 0x2, 8, { W(IR_SENSOR_ID), W(0) } },
 * then (Windows _poweroff) 0x81 {IR_ASYNC} and the 0xa4 {2, A/B, 0..2, 0} steps. */
#undef W
