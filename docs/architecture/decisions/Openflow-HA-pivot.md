This design document outlines the architecture for a high-availability (HA), software-defined gateway using **NixOS**, a **Brocade 6610** switch, and the **WAS-111** XGS-PON SFP+ module to bypass the AT&T BGW320 gateway.

---

# Project: Nautical-HA Gateway (WAS-111 Bypass)
**Status:** Design Phase  
**Nodes:** `topsail`, `stormjib`  
**Infrastructure:** Brocade 6610 (OpenFlow enabled), WAS-111 (XGS-PON SFP+)

## 1. Objective
Replace the ISP-provided gateway with a redundant, declarative NixOS routing cluster. The goal is to achieve **zero-downtime maintenance**, **persistent TCP sessions** during failover, and **line-rate 10Gbps performance** using hardware-accelerated OpenFlow switching.

---

## 2. Hardware Architecture
The physical layout separates the high-bandwidth data plane from the management and state-synchronization plane.

| Component | Specification | Role |
| :--- | :--- | :--- |
| **Brocade 6610** | 24x1G, 16x10G SFP+ | The OpenFlow Data Plane / L2 Fabric. |
| **WAS-111** | XGS-PON SFP+ | Fiber termination; masquerades as BGW320. |
| **Nodes A & B** | 10G SFP+ capable | *topsail* and *stormjib* (NixOS Router nodes). |

### Physical Port Mapping (Logical)
* **Switch Port 1/1/1:** WAS-111 (Input from AT&T).
* **Router Port 1 (SFP+):** Dedicated WAN Data Plane (OpenFlow virtual wire target).
* **Router Port 2 (SFP+/RJ45):** Management, VRRP Heartbeat, and `conntrackd` sync.

---

## 3. Networking & HA Strategy
The system utilizes a "Warm Standby" active-passive model.

### 3.1 Layer 2 (OpenFlow Control)
To prevent MAC flapping and duplicate IP conflicts, the Brocade 6610 uses **Hybrid Port Mode**. 
* **The Virtual Wire:** OpenFlow rules ensure that traffic from Port 1/1/1 (WAS-111) is shunted **only** to the active node's Port 1.
* **The Controller:** Both nodes run an OpenFlow controller (e.g., Faucet). The switch connects to a **Virtual IP (VIP)** shared by the nodes.

### 3.2 Layer 3 (Routing & VIP)
* **Keepalived (VRRP):** Manages the Public IP (WAN) and Internal Gateway IP (LAN).
* **Interface Spoofing:** Both nodes spoof the MAC address of the original BGW320 on their WAN interfaces.

### 3.3 Layer 4 (Stateful Synchronization)
To keep sockets open during failover:
* **`conntrackd`:** Mirrored kernel connection tracking table via multicast over Port 2.
* **Kea DHCP:** High-availability "Hot Standby" hook to sync lease databases.



---

## 4. Software Implementation (NixOS)

### 4.1 Declarative Configuration
The entire stack is defined in a Nix Flake. A shared module defines the logic, while `networking.hostName` toggles specific port IDs.

```nix
# High-level logic for OpenFlow pathing
let
  was111Port = "1/1/1";
  activePort = if config.networking.hostName == "topsail" then "1/1/2" else "1/1/3";
in {
  services.faucet.settings.dps.brocade.interfaces."${was111Port}".rules = [
    { allow = true; output = activePort; }
  ];
  
  services.keepalived.enable = true;
  services.conntrackd.enable = true;
  services.kea.dhcp4.settings.high-availability = [ { mode = "hot-standby"; } ];
}
```

---

## 5. Failover & Operational Lifecycle

### 5.1 Failure Detection
1.  **Node A Fails:** Power loss or system hang.
2.  **Keepalived Trigger:** Node B misses VRRP advertisements (default <1s).
3.  **VIP Takeover:** Node B claims the WAN/LAN VIPs.

### 5.2 The "Handover" Sequence
1.  **State Commit:** `conntrackd` flushes the mirrored table into the kernel.
2.  **SDN Repoint:** Node B (now Master) updates the OpenFlow controller. The Brocade 6610 updates its TCAM to point WAS-111 traffic to Node B's Port 1.
3.  **Gratuitous ARP:** Node B sends a GARP to the upstream AT&T OLT to update the physical path for the spoofed MAC.

### 5.3 Maintenance Mode (Updates)
1.  Apply `nixos-rebuild switch` to the **Standby** node.
2.  Verify sync status (`conntrackd -s`).
3.  Stop `keepalived` on the Active node to force a controlled failover.
4.  Apply update to the now-Standby node.

---

## 6. Critical Caveats
* **MTU/VLAN 0:** WAS-111 must be configured to strip/fix VLAN 0 tagging before traffic hits the Brocade.
* **Fail-Secure:** Brocade 6610 must be set to `fail-secure` mode so that if the controller connection blips, the hardware continues passing traffic based on the last known-good flows.
* **SFP+ Sync:** Verify Brocade `speed-group` settings for 2.5G/5G compatibility with the WAS-111.

---

## 7. Implementation Checklist
* [ ] Flash WAS-111 with 8311 community firmware and clone credentials.
* [ ] Configure Brocade 6610 for Hybrid-Port OpenFlow.
* [ ] Implement `conntrackd` and `Keepalived` NixOS modules.
* [ ] Configure Kea DHCP HA hooks.
* [ ] Deploy Faucet/Ryu controller with REST API or "Route-to-me" logic.
* [ ] Perform "Pull the Plug" test on `topsail` while monitoring a live AI inference stream on `astrolabe`.
