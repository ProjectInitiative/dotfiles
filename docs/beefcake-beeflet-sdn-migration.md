# SDN Migration: Beefcake (Brocade ICX 6610) + Beeflet (MikroTik CRS)

**Status:** In progress — static config stable, Faucet/OpenFlow pending  
**Previous session:** 2026-05-16  
**Repo:** `/home/kylepzak/development/docs/switches/6610-beefcake/`

---

## Current Topology (Fully Working, Static Config)

```
┌─────────────────────────────────────────────────────────────┐
│                  BROCADE ICX 6610 (beefcake)                │
│  Module 1: 48x 1G RJ45 (icx6610-48p-poe)                   │
│  Module 2: QSFP breakout → 10x 10G (icx6610-qsfp)          │
│  Module 3: 8x 10G SFP+ (icx6610-8-port-10g)                │
│                                                             │
│  LAG "beeflet"  (ID 4): 1/2/5 + 1/2/10  ───┐              │
│  LAG "server1"  (ID 1): 1/2/2 + 1/2/7       │              │
│  LAG "server2"  (ID 2): 1/2/3 + 1/2/8       │              │
│  LAG "server3"  (ID 3): 1/2/4 + 1/2/9       │              │
│                                              │              │
│  1/3/1: 10GE LR → router uplink              │              │
│  1/3/3: 10GE SR → k8s-backplane (VLAN 10)    │              │
│  1/3/4: 10GE SR                              │              │
│                                              │              │
│  MGMT IP: 172.16.1.15/24 on ve1              │              │
└──────────────────────────────────────────────┘              │
                                                 │            │
                      ┌──────────────────────────┘            │
                      │  LACP bond (802.3ad)                  │
                      ▼                                       │
┌─────────────────────────────────────────────────────────┐   │
│                MIKROTIK (beeflet)                        │   │
│  sfp-sfpplus1 + sfp-sfpplus2 → bond-beefcake → bridge   │   │
│  ether1-8 → bridge                                      │   │
└─────────────────────────────────────────────────────────┘   │
```

### Current VLAN Map (Running on Brocade)

| VID  | Name              | Purpose                                        |
| ---- | ----------------- | ---------------------------------------------- |
| 1    | mgmnt             | Management (untagged on LAG + 1/3/1)           |
| 2    | stable-net        | Stable/home network (tagged on most 1/1 ports) |
| 3    | backup-wan        | Backup WAN (1/1/5 untagged)                    |
| 10   | k8s-backplane     | Kubernetes/storage (untagged on server LAGs)   |
| 21   | Network-Not-Found | VoIP (tagged on most 1/1 ports)                |
| 1024 | DEFAULT-VLAN      | Default (router-if ve1)                        |
| 2048 | wap-mgmnt         | WAP management                                 |

---

## What Was Done This Session

1. **Diagnosed dead port 1/2/5** — showed `DOWN, BLOCKING`, media detected but no link
   - Confirmed cable works on port 1/3/5 (port is fine, not cable)
   - AOC breakout cable verified functional
2. **Cleaned up LAG config** — recreated LAG "beeflet" ID 4 with 1/2/5 + 1/2/10
3. **MikroTik soft-brick recovery** — `/interface bridge port remove [find]` stripped all bridge ports, requiring serial console recovery at 115200 baud
4. **MikroTik reconfigure** — bridge+bond recreated, LACP on sfp-sfpplus1+sfp-sfpplus2
5. **Brocade power cycle** — full cold boot fixed the dead QSFP lane on 1/2/5
6. **Drafted faucet.yaml** — Faucet SDN config for L2 fabric with ACLs (see `/home/kylepzak/development/docs/switches/6610-beefcake/faucet.yaml`)

### Gotcha: The Dead QSFP Lane

Port 1/2/5 came back after a **full power-off power cycle** (unplug for 30s). Software `disable/enable` and `reload` did NOT fix it. This is a known ICX 6610 quirk — the QSFP module's internal SERDES can wedge on individual breakout lanes after VLAN/config changes. Cold boot fully re-initializes the module's backplane connection.

---

## Faucet SDN Migration Plan

### Target Architecture

```
┌─────────────┐   Faucet Controller (capstan-gw)   ┌─────────────┐
│  beefcake   │◄──── OpenFlow 1.3 (TCP 6653) ──────►│  beeflet    │
│  (Brocade)  │                                      │  (MikroTik) │
│  dp_id 0x1  │                                      │  dp_id 0x2  │
└──────┬──────┘                                      └──────┬──────┘
       │  LACP (802.3ad, 2x10G tagged all VLANs)            │
       └─────────────────────────────────────────────────────┘
                         │
                    [router_uplink]
                    port 1/3/1 → capstan-gw
                    VLAN subinterfaces on capstan-gw for routing
```

### Target VLANs (New Scheme)

| VID | Name    | Subnet          | Purpose                  |
| --- | ------- | --------------- | ------------------------ |
| 10  | mgmt    | 172.16.10.0/24  | Management plane         |
| 20  | servers | 172.16.20.0/24  | Server/storage backplane |
| 30  | home    | 192.168.30.0/24 | Trusted home LAN         |
| 40  | guest   | 192.168.40.0/24 | Guest wireless           |
| 50  | iot     | 192.168.50.0/24 | IoT devices              |

### Migration Steps (In Order)

#### Phase 1: Enable OpenFlow on Both Switches

**Brocade (beefcake):**

```
enable
configure terminal
openflow
controller tcp <capstan-gw-ip> 6653
enable
exit
write memory
```

**MikroTik (beeflet):**

```
/interface openflow add controller=<capstan-gw-ip> port=6653 name=of-beefcake
```

Test with `/interface openflow print` on beeflet.

#### Phase 2: Verify OF Port Numbers

On the **capstan-gw** Faucet host after Faucet connects:

```
sudo ovs-ofctl dump-ports-desc tcp:127.0.0.1:6654
```

Or check `/var/log/faucet/faucet.log` for port labels.

Update the OF port numbers in `faucet.yaml` to match reality. Current best guesses:

| CLI Port | Est. OF Port | Name          |
| -------- | ------------ | ------------- |
| 1/2/5    | 53           | to_beeflet_a  |
| 1/2/10   | 58           | to_beeflet_b  |
| 1/3/1    | 61           | router_uplink |
| 1/3/3    | 63           | k8s-server    |
| 1/1/1    | 1            | (TBD client)  |

**Important:** The ICX 6610 OF port numbering is not guaranteed — verify empirically.

#### Phase 3: Deploy Faucet Controller

The NixOS Faucet module exists at:

```
modules/nixos/hosts/masthead/faucet.nix
```

This currently handles the WAS-111 bypass (3-port virtual wire). For the beefcake/beeflet fabric, two options:

**Option A:** Create a _new_ NixOS module at `modules/nixos/hosts/beefcake/` with a fresh Faucet config for the full L2 fabric. The existing `masthead/faucet.nix` can be kept or retired depending on whether the WAS-111 bypass is still in use.

**Option B:** Extend `masthead/faucet.nix` to support both the WAS-111 bypass AND the full fabric. Riskier — better to keep them separate.

The `faucet.yaml` at `/home/kylepzak/development/docs/switches/6610-beefcake/faucet.yaml` is the reference config. It should be:

- Either `imported` into the NixOS module via `pkgs.writeText` (existing pattern)
- Or deployed as a static file via `services.faucet.configFile`

#### Phase 4: Migrate VLANs

This is the riskiest phase — requires network downtime.

1. **Reconfigure Brocade VLANs** to match the new scheme:

   ```
   configure terminal
   no vlan 2
   no vlan 3
   no vlan 21
   no vlan 1024
   no vlan 2048
   vlan 10 name mgmt by port
    tagged ethe 1/2/5 ethe 1/2/10
    untagged ethe 1/3/1
   vlan 20 name servers by port
    tagged ethe 1/2/5 ethe 1/2/10
    tagged ethe 1/3/3
    untagged ethe 1/2/2 to 1/2/4 ethe 1/2/7 to 1/2/9
   vlan 30 name home by port
    tagged ethe 1/2/5 ethe 1/2/10
    tagged ethe 1/1/1 to 1/1/4 ...
   ```

   (Full port mapping TBD — current config has complex dual-mode assignments)

2. **Update router subinterfaces** on capstan-gw to match new VLANs
3. **Update DHCP scopes** in Kea (currently in `modules/nixos/hosts/router/dhcp-kea.nix`)

#### Phase 5: Enable Faucet as L2 Fabric

Once VLANs are migrated and the router is routing:

1. Stop Brocade STP (global-stp) — Faucet manages the loop-free topology
2. Enable `faucet.yaml` on the Faucet controller
3. Start with `fail_secure_mode` on the Brocade so traffic continues if the controller drops
4. Verify ACL enforcement (guest→home drops, etc.)

---

## Existing Infrastructure in Dotfiles

### Relevant Modules

| Module           | Path                                      | Notes                                             |
| ---------------- | ----------------------------------------- | ------------------------------------------------- |
| masthead         | `modules/nixos/hosts/masthead/`           | HA router + Faucet (WAS-111 bypass)               |
| router           | `modules/nixos/hosts/router/`             | Generic router (networking, firewall, DHCP, VRRP) |
| faucet (current) | `modules/nixos/hosts/masthead/faucet.nix` | Simple 3-port virtual wire for AT&T fiber bypass  |

### Systems

| Host     | Arch          | Role                                 |
| -------- | ------------- | ------------------------------------ |
| capstan1 | x86_64-linux  | Candidate for Faucet controller      |
| capstan2 | x86_64-linux  | Candidate for Faucet controller (HA) |
| topsail  | aarch64-linux | Existing masthead primary router     |
| stormjib | aarch64-linux | Existing masthead backup router      |

### Key Docs

| Doc                | Path                                                       |
| ------------------ | ---------------------------------------------------------- |
| WAS-111 bypass ADR | `docs/architecture/decisions/Openflow-HA-pivot.md`         |
| Brocade LACP guide | `docs/setup-lacp-brocade.md`                               |
| HA router plan     | `docs/architecture/decisions/0001-ha-router-setup-plan.md` |

---

## Brocade Show Run (Captured 2026-05-16)

For reference when migrating — the current working running-config is saved at:
`/home/kylepzak/development/docs/switches/6610-beefcake/switch_data_20260516_225534.log`

Key config elements:

- **Hostname:** beefcake
- **Mgmt IP:** 172.16.1.15/24 on interface management 1
- **LAGs:** beeflet (ID 4), server1-3 (ID 1-3)
- **STP:** global-stp, 802-1w on VLANs 1,2,21,1024
- **DHCP:** client disabled; static route via 172.16.1.1
- **SNMP:** community "public" ([...])
- **Auth:** admin + root via local db, SSH key only (no telnet)
- **NTP:** Google NTP servers
- **Jumbo frames:** enabled
- **Web mgmt:** HTTPS on mgmt1
- **Dual-mode ports:** pervasive on module 1/1 (maps untagged PoE phones to VLAN 21)

---

## Prior Session Handoff

The previous handoff (`HANDOFF.md` at repo root) covers stormjib's 100Mbps issue on its RTL8125 NICs. Not directly related to the switch migration, but stormjib connects through this fabric.

---

## Open Issues / Gotchas

1. **OF port numbers unknown** — must verify after enabling OpenFlow
2. **fail_secure_mode** — Brocade ICX 6610 must use `fail-secure` (not `fail-standalone`) to keep last-good flows on controller disconnection
3. **Dual-mode migration** — Brocade's `dual-mode <vlan>` on 1/1 ports is a proprietary feature. The new scheme eliminates this; PoE phones currently on VLAN 21 will need their config updated
4. **LACP vs Faucet bundles** — Faucet handles LACP at the `lacp:` interface key. The ICX 6610 LAG must still exist in the Brocade CLI (LAG is a hardware construct below OF), but Faucet learns bundle membership via LACP
5. **MikroTik OF limitations** — MikroTik's OpenFlow 1.3 single-table mode is basic. It may not support `lacp:` bundle matching in Faucet the same way. Test LACP trunk spanning both switches under Faucet control
6. **Monitoring** — The `icx-monitor` tool at `/home/kylepzak/development/docs/switches/6610-beefcake/` will be partially blind after OpenFlow takes over (CLI-based parsing won't show Faucet-managed flows). Consider adding Prometheus/Faucet metrics dashboards
