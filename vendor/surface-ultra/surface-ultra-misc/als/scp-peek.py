#!/usr/bin/python3
"""Print the SCP reset-doorbell IRQ counter and the newest SCP log lines (read-only, root)."""
import ctypes, os, sys
libc = ctypes.CDLL(None, use_errno=True)
libc.mmap.restype = ctypes.c_void_p
libc.mmap.argtypes = [ctypes.c_void_p, ctypes.c_size_t, ctypes.c_int, ctypes.c_int, ctypes.c_int, ctypes.c_long]
fd = os.open("/dev/mem", os.O_RDONLY | os.O_SYNC)
base = libc.mmap(None, 0x80000, 1, 1, fd, 0x1A800000)
rd = lambda pa: ctypes.c_uint32.from_address(base + pa - 0x1A800000).value
print(f"SCP IRQ52 (SENH reset doorbell) hits: {rd(0x1A86A208)}")
w, n = rd(0x1A87605C), rd(0x1A876060) & 0xFFFF
for i in range(max(0, w - int(sys.argv[1] if len(sys.argv) > 1 else 8)), w):
    e = 0x1A876064 + (i % n) * 0x80
    b = b"".join(rd(e + j).to_bytes(4, "little") for j in range(0, 0x80, 4))
    print("   " + b.split(b"\0")[0].decode("ascii", "replace").strip())
