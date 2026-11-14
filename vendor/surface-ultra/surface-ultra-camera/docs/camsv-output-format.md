# camsv_b output format (FORMAT_TAG2, CENTRAL +0x594)

(Japanese: [camsv-output-format_jp.md](camsv-output-format_jp.md))

Sweep on 2026-11-04 (one capture per value, 3840-byte lines, front camera,
OV02C10 sending RAW10). Windows writes 0x1 (MTK packed RAW10).

| Value | Result |
|---|---|
| 0x1 | MTK packed RAW10 (`MBGA`), what Windows and surface-ultra-camera 0.1 use |
| 0x0 | 8-bit output, 1920 bytes per line (pixel depth field: 0 RAW8, 1 RAW10) |
| 0x2 | RAW12: no frames, and camsv stays wedged (every later frame dropped) until it is soft-reset (`camsv_reset()`, MTK `sv_reset` + `sv_reset_by_camsys_top`) |
| **0x41** (bit 6) | **unpacked 10-bit in 16-bit little-endian words** (`V4L2_PIX_FMT_SGBRG10`), 3840 bytes per line, values 55..1023, upper 6 bits zero. Read by libcamera's SoftISP (CPU and GPU) |
| 0x9 (bit 3) | data, but no known packing |
| 0x11 (bit 4) | frames complete, buffer all zero |
| 0x801 (bit 11) | MTK packed, only ~16 % of the buffer written |
| bits 5, 7-10, 12-20 | no visible change (MTK packed) |
| **0x200001 (bit 21)** | **froze the whole machine (black screen, hard reset needed). Never set it.** |
| bits 22-31 | not tested |

No CSI-2 packed (`SGBRG10P`) setting was found in bits 3-20. Unpacked 16-bit is
enough for SoftISP. (These tests ran at 1920 columns; the driver now grabs
1928, see [how-it-works](how-it-works.md#raw-format).) A 1928x1080 frame is
4164480 bytes, just under the 4 MiB contiguous DMA limit of this machine (no CMA).
