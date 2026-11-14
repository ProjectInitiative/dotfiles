# ratedtdp-probe

Prints which RATED_TDP request each arbitration client of an NVIDIA GPU is making. Read-only: it only issues
`NV2080_CTRL_CMD_PERF_RATED_TDP_GET_CONTROL` (`0x2080206e`).

It is an `LD_PRELOAD` library. It waits for the program it is loaded into (e.g. `nvidia-smi`) to talk to the GPU,
then reuses that program's RM handles for its own queries. No root and no driver changes are needed.

## Build and run

```
make
LD_PRELOAD=$PWD/ratedtdp-probe.so nvidia-smi -L
```

```
RATED_TDP RM      rc=0 status=0 action=0 DEFAULT vpstate=0
RATED_TDP WAR     rc=0 status=0 action=0 DEFAULT vpstate=0
RATED_TDP GLOBAL  rc=0 status=0 action=0 DEFAULT vpstate=0
RATED_TDP PROFILE rc=0 status=0 action=0 DEFAULT vpstate=1
RATED_TDP OS      rc=0 status=0 action=0 DEFAULT vpstate=1
GPU 0: NVIDIA RTX Spark N1X (6144-core Blackwell RTX GPU) (UUID: ...)
```

That is the output on a Surface Laptop Ultra (N1X, driver 620.70.06, AC power), which does not have the ~750 MHz
floor.

## Reading it

- The clients are listed from highest to lowest priority. The GPU follows the first one whose action is not
  `DEFAULT` (`ctrl2080perf.h`, `NV2080_CTRL_PERF_RATED_TDP_CLIENT`).
- `RM` is the driver's own client. Per `ctrl2080perf.h`, it asks for `FORCE_LIMIT` "when no power controllers are
  active".
- `FORCE_LIMIT` holds the GPU at its rated-TDP point. On the Surface, setting `GLOBAL` to `FORCE_LIMIT` took the
  GPU under load from 2379 MHz / 49.6 W to 741 MHz / 12.5 W, and `DEFAULT` brought it back.
- So on an N1X laptop stuck at ~750 MHz on AC, `RM ... FORCE_LIMIT` here would point to the RATED_TDP arbitration
  as the cause. This is a guess to be checked; I have only one machine, and it is not affected.
- `status` other than `0` means the query itself failed (e.g. `0x56`, `NV_ERR_NOT_SUPPORTED`).

## Notes

- The full arbitration state (`NV2080_CTRL_PERF_RATED_TDP_STATUS_PARAMS`, including `rm.clientActiveMask`) is not
  readable from user space on this setup; only the per-client requests are.
- Run it once at idle and once while the GPU is under load, if the clock floor only appears under load.
- Tested with the open kernel modules 620.70.06 on aarch64. The control has existed for years, so other versions
  likely work too.
