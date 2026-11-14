// nvpcf-shim: LD_PRELOAD shim for nvidia-powerd on NVIDIA N1x.
//
// The N1x platform firmware answers the NVPCF _DSM only at revision 0x300. nvidia-powerd
// 620 detects 3x but creates its workers (QBoost/JPAC) only on the 1x/2x path, and those
// workers read 2x data. This shim makes powerd see a 2x NVPCF platform by answering the
// parsed NV0000_CTRL_CMD_SYSTEM_NVPCF_GET_POWER_MODE_INFO results itself:
//
//   3x (any sub)       -> NOT_SUPPORTED          (SHIM_HIDE3X=1)  factory falls to 2x path
//   2x GET_SUPPORTED   -> mask (static, dynamic, DC sys power limits, CPU TDP)
//   2x GET_STATIC      -> v22 table, one PPAB (QBoost) controller, CPU type NVIDIA
//   2x GET_DYNAMIC     -> enabled on AC and DC, zero offsets
//   2x DC_SYSPWR       -> v20, one entry at 100%: battery current limits from the
//                         platform's own NPCF DDPD (11800 mA long, 15800 mA short)
//   2x CPU_TDP (write) -> recorded (SHIM_CPUTDP_FILE) and logged; not applied yet
//
// Every other RM control is passed through and logged, to find where powerd writes its
// control targets.
//
// Build: gcc -O2 -Wall -shared -fPIC -I<open-gpu-kernel-modules>/src/common/sdk/nvidia/inc
//   -o nvpcf-shim.so nvpcf-shim.c -ldl  (one line)
#define _GNU_SOURCE
#include <dlfcn.h>
#include <fcntl.h>
#include <stdarg.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <time.h>
#include <unistd.h>
#include <sys/mman.h>
#include <glob.h>
#include <pthread.h>
#include <math.h>

#include "nvtypes.h"
#include "ctrl/ctrl0000/ctrl0000system.h"

typedef NV0000_CTRL_SYSTEM_NVPCF_GET_POWER_MODE_INFO_PARAMS pcf_t;

#define NV_IOCTL_MAGIC 'F'
#define NV_ESC_RM_CONTROL 0x2A
#define NV_OK 0
#define NV_ERR_NOT_SUPPORTED 0x56
#define ACPI_DSM_FUNCTION_NVPCF_3X 12

// RM-internal values (src/nvidia/inc/kernel/platform/nvpcf.h, 620.70.06)
#define NVPCF_SYSDEV_STATIC_TABLE_COMMON_2X_PARAM0_CPU_TYPE_NVIDIA 2
#define NVPCF_SYSDEV_STATIC_TABLE_COMMON_2X_PARAM0_GPU_TYPE_NVIDIA 0
#define NVPCF0100_CTRL_CONTROLLER_FILTER_TYPE_EMWA 0
#define NVPCF_DC_SYSTEM_POWER_LIMITS_TABLE_VERSION_20 0x20

typedef struct {               // NVOS54_PARAMETERS
    uint32_t hClient, hObject, cmd, flags;
    uint64_t params;
    uint32_t paramsSize;
    uint32_t status;
} nvos54_t;

static int (*real_ioctl)(int, unsigned long, ...);
static void lg(const char *fmt, ...) __attribute__((format(printf, 1, 2)));
static int logfd = -1;
static int hide3x = 1;
static uint32_t mask2x = 0x307;          // bit0 get-supported, 1 static, 2 dynamic, 8 DC limits, 9 CPU TDP
static uint8_t  static_ver = 0x22;
static uint32_t dc_long_ma = 11800, dc_short_ma = 15800;
static const char *cputdp_file;
static const char *dump_dir;
static int fake_policy;
static int tgp_policy = 2;
static uint32_t tgp_max_mw = 60000;        // realistic limit presented for the TGP policy
static int fix_powersrc = 1;               // answer PERF_GET_POWERSTATE from ADP1/online
static int fake_setlimit = 1;              // accept 0x2080e634 (GSP returns NOT_SUPPORTED on N1x)
// ---------- budget test: issue limits to GSP with powerd's own RM handles ----------
static int cap_fd = -1; static unsigned long cap_req; static uint32_t cap_client, cap_subdev;
static uint8_t e634_last[808]; static int e634_have;
static const char *test_mode; static int test_at = 20, test_dur = 25;

static uint32_t rm_ctrl(uint32_t cmd, void *p, uint32_t size)
{
    nvos54_t c = { cap_client, cap_subdev, cmd, 0, (uint64_t)(uintptr_t)p, size, 0 };
    int r = real_ioctl(cap_fd, cap_req, &c);
    return r ? 0xffffffffu : c.status;
}

static void *test_thread(void *unused)
{
    (void)unused;
    for (int i = 0; i < 100 && cap_fd < 0; i++) sleep(1);
    sleep(test_at);
    if (cap_fd < 0) { lg("TEST: no RM handles captured"); return NULL; }
    if (!strcmp(test_mode, "ratedtdp")) {
        uint32_t st[64] = {0};
        uint32_t s0 = rm_ctrl(0x2080206d, st, sizeof st);          // RATED_TDP_GET_STATUS
        lg("TEST ratedtdp: GET_STATUS st=%#x out=%u", s0, st[3]);
        uint32_t ctl[3] = { 2 /*GLOBAL*/, 2 /*FORCE_LIMIT*/, 0 /*VPSTATE_RATED_TDP*/ };
        uint32_t s1 = rm_ctrl(0x2080206f, ctl, sizeof ctl);         // RATED_TDP_SET_CONTROL
        memset(st, 0, sizeof st); rm_ctrl(0x2080206d, st, sizeof st);
        lg("TEST ratedtdp: SET FORCE_LIMIT st=%#x -> status out=%u  (LIMIT ON)", s1, st[3]);
        sleep(test_dur);
        uint32_t ctl0[3] = { 2, 0 /*DEFAULT*/, 0 };
        uint32_t s2 = rm_ctrl(0x2080206f, ctl0, sizeof ctl0);
        lg("TEST ratedtdp: SET DEFAULT st=%#x  (LIMIT OFF)", s2);
    } else if (!strcmp(test_mode, "ratedget")) {
        static const char *cn[] = {"RM","WAR","GLOBAL","PROFILE","OS"};
        for (int pass = 0; pass < 3; pass++) {
            if (pass == 1) { uint32_t ctl[3] = {2, 2, 0}; lg("TEST ratedget: SET GLOBAL FORCE_LIMIT st=%#x", rm_ctrl(0x2080206f, ctl, sizeof ctl)); sleep(2); }
            if (pass == 2) { uint32_t ctl[3] = {2, 0, 0}; lg("TEST ratedget: SET GLOBAL DEFAULT st=%#x", rm_ctrl(0x2080206f, ctl, sizeof ctl)); sleep(2); }
            for (uint32_t cl = 0; cl < 5; cl++) {
                uint32_t g[3] = { cl, 0xffffffff, 0xffffffff };
                uint32_t st = rm_ctrl(0x2080206e, g, sizeof g);         // RATED_TDP_GET_CONTROL
                lg("TEST ratedget pass%d: client %-7s st=%#x action=%u vpstate=%u", pass, cn[cl], st, g[1], g[2]);
            }
        }
    } else if (!strncmp(test_mode, "e634:", 5)) {
        uint32_t mw = strtoul(test_mode + 5, NULL, 0);
        if (!e634_have) { lg("TEST e634: no template captured"); return NULL; }
        uint8_t b[808]; memcpy(b, e634_last, sizeof b);
        uint32_t orig; memcpy(&orig, b + 44, 4); memcpy(b + 44, &mw, 4);
        uint32_t s1 = rm_ctrl(0x2080e634, b, sizeof b);
        lg("TEST e634: real SET limit %u mW -> st=%#x  (LIMIT ON)", mw, s1);
        sleep(test_dur);
        memcpy(b, e634_last, sizeof b);
        uint32_t s2 = rm_ctrl(0x2080e634, b, sizeof b);
        lg("TEST e634: real SET back %u mW -> st=%#x  (LIMIT OFF)", orig, s2);
    }
    return NULL;
}   // 0x2080a618 policy index to present as the TGP policy

// ---------- virtual x86 MSR (powerd's QBoost host interface is RAPL over /dev/cpu/N/msr) ----------
static int fake_msr, fake_vendor;
static int msr_fds[64];
static double tdp_w = 30, pl1_w = 45, pl2_w = 64;
static char psoc_path[256], psys_path[256];
static uint64_t msr_610, msr_65c;          // last written power limits
static int msr_610_set;
static double e_pkg_j, e_sys_j;            // integrated energy
static struct timespec e_last;
static uint8_t seen_msr[4096];

// GPU power from NVML (cached 1 s), so the virtual CPU package does not count the GPU twice
static double gpu_w_cached; static struct timespec gpu_ts;
static double gpu_w(void)
{
    static int (*init)(void), (*byidx)(unsigned, void **), (*pw)(void *, unsigned *);
    static void *dev; static int tried;
    struct timespec now; clock_gettime(CLOCK_MONOTONIC, &now);
    if (gpu_ts.tv_sec && now.tv_sec - gpu_ts.tv_sec < 1) return gpu_w_cached;
    gpu_ts = now;
    if (!tried) {
        tried = 1;
        void *h = dlopen("libnvidia-ml.so.1", RTLD_NOW | RTLD_LOCAL);
        if (h) { init = dlsym(h, "nvmlInit_v2"); byidx = dlsym(h, "nvmlDeviceGetHandleByIndex_v2"); pw = dlsym(h, "nvmlDeviceGetPowerUsage"); }
        if (!(init && byidx && pw) || init() || byidx(0, &dev)) { dev = NULL; lg("NVML unavailable; CPU power = PSOC"); }
    }
    unsigned mw = 0;
    if (dev && pw(dev, &mw) == 0) gpu_w_cached = mw / 1000.0;
    return gpu_w_cached;
}

static double zone_w(const char *path)      // ACPI \_TZ.PSOC / PSYS report mW through the dK conversion
{
    if (!path[0]) return 0;
    int fd = open(path, O_RDONLY | O_CLOEXEC);
    if (fd < 0) return 0;
    char b[32] = {0};
    ssize_t n = read(fd, b, sizeof b - 1);
    close(fd);
    if (n <= 0) return 0;
    return (strtol(b, NULL, 10) / 100.0 + 2732.0) / 1000.0;
}

static void find_zone(const char *name, char *out)
{
    glob_t g;
    if (glob("/sys/class/thermal/thermal_zone*", 0, NULL, &g)) return;
    for (size_t i = 0; i < g.gl_pathc; i++) {
        char p[256], v[64] = {0};
        snprintf(p, sizeof p, "%s/device/path", g.gl_pathv[i]);
        int fd = open(p, O_RDONLY | O_CLOEXEC);
        if (fd < 0) continue;
        ssize_t n = read(fd, v, sizeof v - 1);
        close(fd);
        if (n > 0 && strstr(v, name)) { snprintf(out, 256, "%s/temp", g.gl_pathv[i]); break; }
    }
    globfree(&g);
}

static int is_msr_fd(int fd)
{
    for (int i = 0; i < 64; i++) if (msr_fds[i] == fd && fd > 0) return 1;
    return 0;
}

static void energy_tick(void)
{
    struct timespec now;
    clock_gettime(CLOCK_MONOTONIC, &now);
    if (e_last.tv_sec) {
        double dt = (now.tv_sec - e_last.tv_sec) + (now.tv_nsec - e_last.tv_nsec) / 1e9;
        double cpu = zone_w(psoc_path) - gpu_w();
        if (cpu < 1.0) cpu = 1.0;
        e_pkg_j += cpu * dt;
        e_sys_j += zone_w(psys_path) * dt;
    }
    e_last = now;
}

#define PU 3   // power unit 1/8 W
#define ESU 14 // energy unit 1/16384 J
#define TU 10  // time unit 1/1024 s
static uint64_t msr_read(uint32_t r)
{
    uint64_t pl;
    switch (r) {
    case 0x606: return (uint64_t)PU | ((uint64_t)ESU << 8) | ((uint64_t)TU << 16);
    case 0x611: energy_tick(); return (uint32_t)(e_pkg_j * (1 << ESU));
    case 0x64d: energy_tick(); return (uint32_t)(e_sys_j * (1 << ESU));
    case 0x614: return (uint64_t)(tdp_w * 8) | ((uint64_t)(5 * 8) << 16) | ((uint64_t)(80 * 8) << 32) | (0x0aULL << 48);
    case 0x610:
        if (msr_610_set) return msr_610;
        pl = (uint64_t)(pl1_w * 8) | (1ULL << 15) | (0x6eULL << 17);
        pl |= ((uint64_t)(pl2_w * 8) << 32) | (1ULL << 47);
        return pl;
    case 0x65c: return msr_65c;
    default:
        if (r < sizeof seen_msr && !seen_msr[r]) { seen_msr[r] = 1; lg("MSR read %#x -> 0 (unmodelled)", r); }
        else if (r >= sizeof seen_msr) lg("MSR read %#x -> 0 (unmodelled)", r);
        return 0;
    }
}

static void msr_write(uint32_t r, uint64_t v)
{
    if (r == 0x610) {
        msr_610 = v; msr_610_set = 1;
        lg("MSR WRITE PKG_POWER_LIMIT %#llx: PL1=%.2fW en=%d  PL2=%.2fW en=%d",
           (unsigned long long)v, (v & 0x7fff) / 8.0, (int)((v >> 15) & 1),
           ((v >> 32) & 0x7fff) / 8.0, (int)((v >> 47) & 1));
    } else if (r == 0x65c) {
        msr_65c = v;
        lg("MSR WRITE PLATFORM_POWER_LIMIT %#llx: PL1=%.2fW PL2=%.2fW", (unsigned long long)v,
           (v & 0x1ffff) / 8.0, ((v >> 32) & 0x1ffff) / 8.0);
    } else {
        lg("MSR WRITE %#x = %#llx", r, (unsigned long long)v);
    }
}
static uint32_t dump_cmds[8]; static int ndump;

static unsigned envu(const char *n, unsigned d)
{
    const char *v = getenv(n);
    return v ? (unsigned)strtoul(v, NULL, 0) : d;
}

static void lg(const char *fmt, ...)
{
    if (logfd < 0)
        return;
    char buf[640];
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    int n = snprintf(buf, sizeof buf, "%ld.%03ld [%d] ", (long)ts.tv_sec, ts.tv_nsec / 1000000, getpid());
    va_list ap;
    va_start(ap, fmt);
    n += vsnprintf(buf + n, sizeof buf - n, fmt, ap);
    va_end(ap);
    if (n > (int)sizeof buf - 2)
        n = sizeof buf - 2;
    buf[n++] = '\n';
    if (write(logfd, buf, n) < 0) { /* ignore */ }
}

__attribute__((constructor)) static void init(void)
{
    real_ioctl = dlsym(RTLD_NEXT, "ioctl");
    const char *p = getenv("SHIM_LOG");
    logfd = open(p ? p : "/tmp/nvpcf-shim.log", O_WRONLY | O_CREAT | O_APPEND | O_CLOEXEC, 0644);
    hide3x      = envu("SHIM_HIDE3X", 1);
    mask2x      = envu("SHIM_MASK2X", mask2x);
    static_ver  = envu("SHIM_STATIC_VER", static_ver);
    dc_long_ma  = envu("SHIM_DC_LONG_MA", dc_long_ma);
    dc_short_ma = envu("SHIM_DC_SHORT_MA", dc_short_ma);
    cputdp_file = getenv("SHIM_CPUTDP_FILE");
    dump_dir    = getenv("SHIM_DUMP_DIR");
    fake_policy = envu("SHIM_FAKE_POLICY", 0);
    tgp_policy  = envu("SHIM_TGP_POLICY", tgp_policy);
    tgp_max_mw  = envu("SHIM_TGP_MAX_MW", tgp_max_mw);
    fix_powersrc = envu("SHIM_POWERSRC", fix_powersrc);
    fake_setlimit = envu("SHIM_FAKE_SETLIMIT", fake_setlimit);
    fake_msr    = envu("SHIM_FAKE_MSR", 0);
    fake_vendor = envu("SHIM_FAKE_VENDOR", fake_msr);
    if (getenv("SHIM_TDP_W")) tdp_w = atof(getenv("SHIM_TDP_W"));
    if (getenv("SHIM_PL1_W")) pl1_w = atof(getenv("SHIM_PL1_W"));
    if (getenv("SHIM_PL2_W")) pl2_w = atof(getenv("SHIM_PL2_W"));
    e_pkg_j = e_sys_j = 1000.0;   // real RAPL counters are never 0; powerd treats 0 as "no RAPL"
    find_zone("PSOC", psoc_path);
    find_zone("PSYS", psys_path);
    test_mode = getenv("SHIM_TEST");
    test_at   = envu("SHIM_TEST_AT", test_at);
    test_dur  = envu("SHIM_TEST_DUR", test_dur);
    if (test_mode && !strcmp(test_mode, "ratedget_now")) { fix_powersrc = 0; fake_setlimit = 0; hide3x = 0; }
    else if (test_mode && *test_mode) { pthread_t t; pthread_create(&t, NULL, test_thread, NULL); pthread_detach(t); }
    if (getenv("SHIM_DUMP_CMDS")) {           // comma-separated hex cmd list
        char tmp[256]; snprintf(tmp, sizeof tmp, "%s", getenv("SHIM_DUMP_CMDS"));
        for (char *t = strtok(tmp, ","); t && ndump < 8; t = strtok(NULL, ","))
            dump_cmds[ndump++] = strtoul(t, NULL, 0);
    }
    lg("shim v1.9 loaded hide3x=%d mask2x=%#x static=%#x dc=%u/%u mA",
       hide3x, mask2x, static_ver, dc_long_ma, dc_short_ma);
}

// Returns 1 if handled (status set, real ioctl skipped).
static int handle_pcf(nvos54_t *c, pcf_t *p)
{
    if (p->nvpcfFunc == ACPI_DSM_FUNCTION_NVPCF_3X) {
        if (!hide3x)
            return 0;
        c->status = NV_ERR_NOT_SUPPORTED;
        lg("NVPCF 3x sub=%u -> HIDDEN", p->subFunc);
        return 1;
    }

    switch (p->subFunc) {
    case NVPCF0100_CTRL_CONFIG_DSM_2X_FUNC_GET_SUPPORTED_CASE:
        p->supportedFuncs = mask2x;
        lg("2x GET_SUPPORTED -> %#x", mask2x);
        break;

    case NVPCF0100_CTRL_CONFIG_DSM_2X_FUNC_GET_STATIC_CASE:
        // as _sysDeviceParseStaticTable_2x + _controllerParseStaticTable_v22 with one PPAB entry
        p->cpuType            = NVPCF_SYSDEV_STATIC_TABLE_COMMON_2X_PARAM0_CPU_TYPE_NVIDIA;
        p->gpuType            = NVPCF_SYSDEV_STATIC_TABLE_COMMON_2X_PARAM0_GPU_TYPE_NVIDIA;
        p->samplingMulti      = 1;    // CONTROLLER_GRP_DEFAULT_SAMPLING_MULTIPLIER
        p->filterType         = NVPCF0100_CTRL_CONTROLLER_FILTER_TYPE_EMWA;
        p->filterParam.weight = 232;  // CONTROLLER_GRP_DEFAULT_EWMA_WEIGHT
        p->bIsBoostController = NV_TRUE;
        p->incRatio           = 3686; // CONTROLLER_GRP_DEFAULT_INCREASE_GAIN_UFXP4_12
        p->decRatio           = 4096; // CONTROLLER_GRP_DEFAULT_DECREASE_GAIN_UFXP4_12
        p->bSupportBatt       = NV_TRUE;
        p->cpuTdpControlType  = QBOOST_CPU_TDP_CONTROL_TYPE_DC_AC;
        p->version            = static_ver;
        p->samplingPeriodmS   = 100;  // CONTROLLER_GRP_DEFAULT_BASE_SAMPLING_PERIOD_MS
        lg("2x GET_STATIC -> v%#x PPAB, cpu NVIDIA", static_ver);
        break;

    case NVPCF0100_CTRL_CONFIG_DSM_2X_FUNC_GET_DYNAMIC_CASE:
        lg("2x GET_DYNAMIC (in version=%#x)", p->version);
        p->bEnableForAC  = NV_TRUE;
        p->bEnableForDC  = NV_TRUE;
        p->ctgpOffsetmW = p->targetTppOffsetmW = p->maxOutputOffsetmW = p->minOutputOffsetmW = 0;
        p->ctgpBattOffsetmW = p->targetTppBattOffsetmW = 0;
        p->maxOutputBattOffsetmW = 0;        // RM uses QBOOST_LARGE_POSITIVE_MW; powerd then sets 10 kW and fails the range check
        p->minOutputBattOffsetmW = 0;
        p->dcRosReserveOverridemW = 0;
        p->dcTspLongTimescaleLimitOverridemA = 0;
        p->dcTspShortTimescaleLimitOverridemA = 0;
        break;

    case NVPCF0100_CTRL_CONFIG_DSM_2X_FUNC_GET_DC_SYSTEM_POWER_LIMITS_CASE:
        memset(p->sysPwrGetInfo, 0, sizeof p->sysPwrGetInfo);
        p->sysPwrLimitsTableVersion = NVPCF_DC_SYSTEM_POWER_LIMITS_TABLE_VERSION_20;
        p->type            = NVPCF_CTRL_SYSPWRLIMIT_TYPE_BASE;
        p->bIsTspSupported = NV_TRUE;
        p->sysPwrGetInfo[0].batteryStateOfChargePercent         = 100;
        p->sysPwrGetInfo[0].batteryCurrentLimitmA               = dc_long_ma;
        p->sysPwrGetInfo[0].shortTimescaleBatteryCurrentLimitmA = dc_short_ma;
        p->sysPwrGetInfo[0].restOfSytemReservedPowermW          = 0;
        p->sysPwrGetInfo[0].minCpuTdpmW                         = 0;
        p->sysPwrGetInfo[0].maxCpuTdpmW                         = 0xffffffffu;
        p->sysPwrIndex = 1;
        lg("2x DC_SYSPWR -> v20, 100%%: %u/%u mA", dc_long_ma, dc_short_ma);
        break;

    case NVPCF0100_CTRL_CONFIG_DSM_2X_FUNC_CPU_TDP_LIMIT_CONTROL_CASE:
        lg("2x CPU_TDP WRITE cpuTdpmw=%u", p->cpuTdpmw);
        if (cputdp_file) {
            int fd = open(cputdp_file, O_WRONLY | O_CREAT | O_TRUNC | O_CLOEXEC, 0644);
            if (fd >= 0) {
                dprintf(fd, "%u\n", p->cpuTdpmw);
                close(fd);
            }
        }
        break;

    default:
        return 0; // 1x cases etc.: pass through (they fail on N1x)
    }
    c->status = NV_OK;
    return 1;
}

int ioctl(int fd, unsigned long req, ...)
{
    va_list ap;
    va_start(ap, req);
    void *arg = va_arg(ap, void *);
    va_end(ap);

    if (_IOC_TYPE(req) != NV_IOCTL_MAGIC || _IOC_NR(req) != NV_ESC_RM_CONTROL ||
        _IOC_SIZE(req) != sizeof(nvos54_t))
        return real_ioctl(fd, req, arg);

    nvos54_t *c = arg;
    if (cap_fd < 0 && (c->cmd >> 16) == 0x2080) {
        cap_client = c->hClient; cap_subdev = c->hObject; cap_req = req; cap_fd = fd;
        if (test_mode && !strcmp(test_mode, "ratedget_now")) {
            static const char *cn[] = {"RM","WAR","GLOBAL","PROFILE","OS"};
            static const char *an[] = {"DEFAULT","FORCE_EXCEED","FORCE_LIMIT","FORCE_LOCK","FORCE_FLOOR"};
            int r0 = real_ioctl(fd, req, arg);           // let the host's own call go first
            for (uint32_t cl = 0; cl < 5; cl++) {
                uint32_t g[3] = { cl, 0xffffffff, 0xffffffff };
                uint32_t st = rm_ctrl(0x2080206e, g, sizeof g);
                fprintf(stderr, "RATED_TDP client %-7s status=%#x action=%u(%s) vpstate=%u\n",
                        cn[cl], st, g[1], g[1] < 5 ? an[g[1]] : "?", g[2]);
            }
            return r0;
        }
    }
    if (c->cmd == NV0000_CTRL_CMD_SYSTEM_NVPCF_GET_POWER_MODE_INFO) {
        pcf_t *p = (pcf_t *)(uintptr_t)c->params;
        if (c->paramsSize != sizeof(pcf_t))
            lg("WARN pcf paramsSize=%u != %zu", c->paramsSize, sizeof(pcf_t));
        else if (handle_pcf(c, p))
            return 0;
        int r = real_ioctl(fd, req, arg);
        lg("NVPCF func=%u sub=%u passthrough -> rc=%d status=%#x", p->nvpcfFunc, p->subFunc, r, c->status);
        return r;
    }

    if (fake_setlimit && c->cmd == 0x2080e634) {
        // private PMGR "set GPU limit" (808 B). GSP answers NOT_SUPPORTED on N1x; record and accept.
        uint32_t *w = (uint32_t *)(uintptr_t)c->params;
        char buf[400]; int n = 0;
        for (int i = 0; i < 24 && i * 4 < (int)c->paramsSize; i++)
            if (w[i]) n += snprintf(buf + n, sizeof buf - n, " [%d]=%u", i * 4, w[i]);
        buf[n] = 0;
        if (dump_dir) {
            char fn[512]; static int sq;
            snprintf(fn, sizeof fn, "%s/2080e634-%d-%d.bin", dump_dir, getpid(), sq++);
            int o = open(fn, O_WRONLY | O_CREAT | O_TRUNC | O_CLOEXEC, 0644);
            if (o >= 0) { if (write(o, w, c->paramsSize) < 0) {} close(o); }
        }
        if (c->paramsSize == sizeof e634_last) { memcpy(e634_last, w, sizeof e634_last); e634_have = 1; }
        lg("GPU SETLIMIT e634 (accepted):%s", buf);
        c->status = NV_OK;
        return 0;
    }
    int r = real_ioctl(fd, req, arg);
    if (fix_powersrc && c->cmd == 0x2080205a && r == 0 && c->paramsSize == 4) {
        uint32_t *ps = (uint32_t *)(uintptr_t)c->params;   // NV2080_CTRL_PERF_POWER_SOURCE_AC=0 / BATTERY=1
        char v[8] = {0};
        int o = open("/sys/class/power_supply/ADP1/online", O_RDONLY | O_CLOEXEC);
        if (o >= 0) { if (read(o, v, sizeof v - 1) < 0) {} close(o); }
        uint32_t want = (v[0] == '1') ? 0 : 1;
        static int once;
        if (*ps != want && !once++) lg("POWERSTATE GSP says %s, ADP1 says %s -> fixing", *ps ? "BATTERY" : "AC", want ? "BATTERY" : "AC");
        *ps = want;
    }
    // 0x2080a630 (private PMGR policy info, 2340 B): u32 mask at +4, 36-byte entries from +0x26,
    // entry byte 0 = policy type. powerd QBoost needs a type-0 entry (fn 0x6ec60).
    if (fake_policy && c->cmd == 0x2080a630 && r == 0 && c->status == 0 && c->paramsSize == 2340) {
        uint8_t *b = (uint8_t *)(uintptr_t)c->params;
        uint32_t mask; memcpy(&mask, b + 4, 4);
        if (!(mask & 1)) {
            mask |= 1; memcpy(b + 4, &mask, 4);
            b[0x26] = 0;
            lg("FAKE policy: a630 mask=%#x entry0 type=0", mask);
        }
    }
    // 0x2080a618 (private PMGR policies, 20512 B): u32 mask at +4, 260-byte entries; the bytes at
    // +0x98/+0x9a name the policy QBoost should use (fn 0x125940). N1x leaves both 0xff.
    if (fake_policy && c->cmd == 0x2080a618 && r == 0 && c->status == 0 && c->paramsSize == 20512) {
        uint8_t *b = (uint8_t *)(uintptr_t)c->params;
        uint32_t mask; memcpy(&mask, b + 4, 4);
        if (b[0x98] == 0xff && b[0x9a] == 0xff && (mask >> tgp_policy & 1)) {
            b[0x98] = tgp_policy;
            if (tgp_max_mw) {
                memcpy(b + 0xd8 + 260 * tgp_policy, &tgp_max_mw, 4);
                memcpy(b + 0xdc + 260 * tgp_policy, &tgp_max_mw, 4);
            }
            uint32_t d8, dc; memcpy(&d8, b + 0xd8 + 260 * tgp_policy, 4); memcpy(&dc, b + 0xdc + 260 * tgp_policy, 4);
            lg("FAKE policy: a618 idx@0x98=%d (type=%u d8=%u dc=%u)", tgp_policy, b[0xd2 + 260 * tgp_policy], d8, dc);
        }
    }
    if (dump_dir)
        for (int i = 0; i < ndump; i++)
            if (dump_cmds[i] == c->cmd) {
                static int seq;
                char fn[512];
                snprintf(fn, sizeof fn, "%s/%08x-%d-%d.bin", dump_dir, c->cmd, getpid(), seq++);
                int o = open(fn, O_WRONLY | O_CREAT | O_TRUNC | O_CLOEXEC, 0644);
                if (o >= 0) { if (write(o, (void *)(uintptr_t)c->params, c->paramsSize) < 0) {} close(o); }
            }
    if (c->paramsSize && c->paramsSize <= 32) {
        uint32_t *w = (uint32_t *)(uintptr_t)c->params;
        char hb[128]; int n = 0;
        for (unsigned i = 0; i < c->paramsSize / 4; i++) n += snprintf(hb + n, sizeof hb - n, " %#x", w[i]);
        lg("RMCTRL cmd=%#010x hObj=%#x size=%u -> rc=%d status=%#x params:%s",
           c->cmd, c->hObject, c->paramsSize, r, c->status, hb);
    } else
        lg("RMCTRL cmd=%#010x hObj=%#x size=%u -> rc=%d status=%#x",
           c->cmd, c->hObject, c->paramsSize, r, c->status);
    return r;
}

// ---------- file interposers for the virtual MSR and the CPU vendor ----------
static int msr_path(const char *p)
{
    int n;
    return p && sscanf(p, "/dev/cpu/%d/msr", &n) == 1;
}

static int fake_msr_open(const char *p)
{
    int fd = open("/dev/null", O_RDWR | O_CLOEXEC);
    for (int i = 0; i < 64; i++) if (msr_fds[i] <= 0) { msr_fds[i] = fd; break; }
    lg("MSR open %s -> fake fd %d", p, fd);
    return fd;
}

int open(const char *p, int flags, ...)
{
    static int (*real)(const char *, int, ...);
    if (!real) real = dlsym(RTLD_NEXT, "open");
    mode_t m = 0;
    if (flags & O_CREAT) { va_list ap; va_start(ap, flags); m = va_arg(ap, int); va_end(ap); }
    if (fake_msr && msr_path(p)) return fake_msr_open(p);
    return real(p, flags, m);
}

int open64(const char *p, int flags, ...)
{
    static int (*real)(const char *, int, ...);
    if (!real) real = dlsym(RTLD_NEXT, "open64");
    mode_t m = 0;
    if (flags & O_CREAT) { va_list ap; va_start(ap, flags); m = va_arg(ap, int); va_end(ap); }
    if (fake_msr && msr_path(p)) return fake_msr_open(p);
    return real(p, flags, m);
}

ssize_t pread(int fd, void *buf, size_t n, off_t off)
{
    static ssize_t (*real)(int, void *, size_t, off_t);
    if (!real) real = dlsym(RTLD_NEXT, "pread");
    if (fake_msr && n == 8 && is_msr_fd(fd)) {
        uint64_t v = msr_read((uint32_t)off);
        memcpy(buf, &v, 8);
        return 8;
    }
    return real(fd, buf, n, off);
}

ssize_t pwrite(int fd, const void *buf, size_t n, off_t off)
{
    static ssize_t (*real)(int, const void *, size_t, off_t);
    if (!real) real = dlsym(RTLD_NEXT, "pwrite");
    if (fake_msr && n == 8 && is_msr_fd(fd)) {
        uint64_t v;
        memcpy(&v, buf, 8);
        msr_write((uint32_t)off, v);
        return 8;
    }
    return real(fd, buf, n, off);
}

int close(int fd)
{
    static int (*real)(int);
    if (!real) real = dlsym(RTLD_NEXT, "close");
    for (int i = 0; i < 64; i++) if (msr_fds[i] == fd && fd > 0) msr_fds[i] = 0;
    return real(fd);
}

static FILE *fake_cpuinfo(FILE *(*real)(const char *, const char *))
{
    FILE *orig = real("/proc/cpuinfo", "r");
    int mfd = memfd_create("cpuinfo", MFD_CLOEXEC);
    if (mfd < 0) return orig;
    dprintf(mfd, "vendor_id\t: GenuineIntel\n");
    if (orig) {
        char b[4096]; size_t k;
        while ((k = fread(b, 1, sizeof b, orig)) > 0) if (write(mfd, b, k) < 0) break;
        fclose(orig);
    }
    lseek(mfd, 0, SEEK_SET);
    return fdopen(mfd, "r");
}

FILE *fopen(const char *p, const char *m)
{
    static FILE *(*real)(const char *, const char *);
    if (!real) real = dlsym(RTLD_NEXT, "fopen");
    if (fake_vendor && p && !strcmp(p, "/proc/cpuinfo") && m && m[0] == 'r') return fake_cpuinfo(real);
    return real(p, m);
}

FILE *fopen64(const char *p, const char *m)
{
    static FILE *(*real)(const char *, const char *);
    if (!real) real = dlsym(RTLD_NEXT, "fopen64");
    if (fake_vendor && p && !strcmp(p, "/proc/cpuinfo") && m && m[0] == 'r') return fake_cpuinfo(real);
    return real(p, m);
}
