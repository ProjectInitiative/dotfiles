// ratedtdp-probe: print the RATED_TDP arbitration inputs of an NVIDIA GPU.
// Read-only. Preload it into nvidia-smi; it reuses nvidia-smi's own RM handles.
//
//   gcc -O2 -shared -fPIC -o ratedtdp-probe.so ratedtdp-probe.c -ldl
//   LD_PRELOAD=./ratedtdp-probe.so nvidia-smi -L
//
// NV2080_CTRL_CMD_PERF_RATED_TDP_GET_CONTROL (0x2080206e) per client, see
// open-gpu-kernel-modules src/common/sdk/nvidia/inc/ctrl/ctrl2080/ctrl2080perf.h.
// Clients are in descending priority; the RM client asks for FORCE_LIMIT
// "when no power controllers are active".
#define _GNU_SOURCE
#include <dlfcn.h>
#include <stdarg.h>
#include <stdint.h>
#include <stdio.h>
#include <sys/ioctl.h>

typedef struct { uint32_t hClient, hObject, cmd, flags; uint64_t params; uint32_t paramsSize, status; } nvos54_t;

int ioctl(int fd, unsigned long req, ...)
{
    static int (*real)(int, unsigned long, ...);
    static int done;
    if (!real) real = dlsym(RTLD_NEXT, "ioctl");
    va_list ap; va_start(ap, req); void *arg = va_arg(ap, void *); va_end(ap);
    int r = real(fd, req, arg);
    if (done || _IOC_TYPE(req) != 'F' || _IOC_NR(req) != 0x2a || _IOC_SIZE(req) != sizeof(nvos54_t))
        return r;
    nvos54_t *c = arg;
    if ((c->cmd >> 16) != 0x2080) return r;      // first subdevice control: borrow its handles
    done = 1;
    static const char *cn[] = {"RM", "WAR", "GLOBAL", "PROFILE", "OS"};
    static const char *an[] = {"DEFAULT", "FORCE_EXCEED", "FORCE_LIMIT", "FORCE_LOCK", "FORCE_FLOOR"};
    for (uint32_t cl = 0; cl < 5; cl++) {
        uint32_t p[3] = { cl, 0xffffffff, 0xffffffff };   // client, action, vPstateType
        nvos54_t g = { c->hClient, c->hObject, 0x2080206e, 0, (uint64_t)(uintptr_t)p, sizeof p, 0 };
        int rr = real(fd, req, &g);
        fprintf(stderr, "RATED_TDP %-7s rc=%d status=%#x action=%u %s vpstate=%u\n",
                cn[cl], rr, g.status, p[1], p[1] < 5 ? an[p[1]] : "?", p[2]);
    }
    return r;
}
