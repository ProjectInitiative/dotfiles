# ccusnoop: capturing the camera setup on Windows

(Japanese: [README_jp.md](README_jp.md))

A small, **read-only** Windows (arm64) kernel driver that was used to obtain the
register tables in `kernel/`. While the Windows camera app is showing video, it
records two things:

1. It polls the CCU RPC mailbox (physical address `0x3C0BC0C8`, and the second
   mailbox at `0x3C0CC0C8`) and records every command Windows sends (feature,
   command id, length, status, payload).
2. Every second, it dumps the camera blocks the CPU can see directly: rxana,
   D-PHY, mac_top, mac_csi, seninf-top/async (protected, so they read as 0),
   all 14 outmuxes, and camsv a/b (including their DMA blocks).

The log is written to `C:\ccusnoop.log` when the driver is stopped. It only
reads and never writes anything to the hardware.

You only need it to port to another machine or sensor, or to re-check the
register tables. Running it requires test-signing mode, which lowers the
security of that Windows install while it is enabled.

## Build

Install Visual Studio 2026, the Windows Driver Kit, and the
"C++ ARM64 build tools" component on Windows 11 arm64. Either create an empty
WDM driver project, add `ccusnoop.c` and build Release/ARM64, or build the
included project from a WDK developer prompt.

```
msbuild ccusnoop.vcxproj /p:Configuration=Release /p:Platform=ARM64
```

## Enable test signing

Run this from an administrator prompt and reboot ("Test Mode" appears on the
desktop).

```
bcdedit /set testsigning on
```

If the unsigned driver still will not load, self-sign it.

```
makecert -r -ss PrivateCertStore -n CN=ccusnoopTest ccusnoopTest.cer
signtool sign /s PrivateCertStore /n ccusnoopTest /fd sha256 ccusnoop.sys
certmgr /add ccusnoopTest.cer /s /r localMachine root
```

## Capture

```
sc create ccusnoop type= kernel binPath= C:\path\to\ccusnoop.sys
sc start ccusnoop
```

Open the Windows Camera app and keep the preview running for a few seconds
(changing the resolution is fine). With the preview still running, run:

```
sc stop ccusnoop
sc delete ccusnoop
```

Stopping it while the camera streams makes the last dump a streaming-state
snapshot. The polling keeps one CPU core busy, so stop it when you are done,
and switch test signing back off (`bcdedit /set testsigning off`).

## Reading the log

Mailbox lines look like this:

```
mb0 w=<sequence> ft=<feature> cmd=0x<id> len=<bytes> st=0x<status> pl: <payload>
```

`ft=4` is seninf. One stream start runs from the first `ft=1 cmd=0xd` to
`ft=4 cmd=0x2` with payload `{1, 1}` (MSG_SENINF_SET_STREAM on). Register
dumps start with `=== DUMP #n ===`, and lines that are all zeros are omitted.
