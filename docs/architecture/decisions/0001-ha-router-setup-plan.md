# 0001: HA Router Setup Architecture Plan

## Context
We need to build a High Availability (HA) NixOS router setup utilizing two rockchip-based nodes: **Topsail** (Primary) and **StormJib** (Backup). The goal is to provide a robust, automated network gateway with minimal downtime, automatic failover, multi-WAN load balancing/failover, failsafe rollbacks, comprehensive monitoring, and migration tooling for existing OpenWrt configurations. This infrastructure will also serve as a foundation for advanced local NPU-accelerated network analysis.

## Goals
- Build a common, role-aware NixOS module system (`masthead`) for both routers.
- Implement HA-aware failover and seamless switching (Keepalived/VRRP, MAC spoofing, dynamic WAN IP handling).
- Support Multi-WAN configurations (load balancing and failover across multiple ISP connections).
- Provide local Virtual IPs (VIPs) for the LAN gateway.
- Ensure automated failsafe rollback mechanisms if network access is lost during configuration updates.
- Centralize metrics gathering (Prometheus, Grafana) for routing, DHCP, and HA state.
- Support multiple VLANs, DHCP servers, and subnet architectures.
- Develop an agent to migrate existing `/etc/config/*` settings from OpenWrt to NixOS.
- Establish an isolated NixOS VM testing framework (`nixosTest`) for the HA and multi-WAN logic.
- **Stretch:** Leverage onboard NPUs (rk3588) for AI-driven network analysis and anomaly detection.
- **Stretch:** Implement dynamic Quality of Service (QoS) and Traffic Shaping to prioritize specific hosts or subnets (e.g., a "work" VLAN) and aggressively throttle non-essential traffic (e.g., servers) when failed over to a metered WAN connection (like Starlink).

## Sub-Agent Groupings and Task Breakdown

To ensure efficient, conflict-free parallel development, tasks are divided into distinct functional groups. Each sub-agent can operate independently within their designated scope and file paths.

### Group 1: Core Base & Networking Foundations (The `masthead` Module)
**Focus:** Define the declarative network topology and the base router module.
**Tasks:**
1. Create the base NixOS module `modules/nixos/hosts/masthead/default.nix`.
2. Define role options: `config.projectinitiative.hosts.masthead.role = "primary" | "backup"`.
3. Implement declarative network configurations for interfaces, VLANs, and bridges (`networking.vlans`, `networking.bridges`).
4. Configure DHCP servers (e.g., `kea` or `dnsmasq`) and DNS resolvers, ensuring they are prepared for HA/sync.
5. Create the specific host definition for `topsail` (similar to the existing `stormjib` host, but with the primary role).

### Group 2: High Availability & Multi-WAN Failover (VRRP/Keepalived/MWAN3)
**Focus:** Handle seamless LAN gateway VIPs, WAN connection failover, and Multi-WAN load balancing.
**Tasks:**
1. Integrate `keepalived` for VRRP to manage local Gateway VIPs on LAN interfaces.
2. Develop Multi-WAN logic (e.g., using policy-based routing with `iproute2` or evaluating packages like `mwan3` equivalents in NixOS). This must handle dynamic WAN IP acquisition, health checks across multiple ISPs, and connection tracking during WAN failover.
3. Integrate HA failover scripts triggered by VRRP state changes, including potential MAC address spoofing on the backup node to satisfy ISP requirements.
4. Implement state synchronization using `conntrackd` to ensure seamless transfer of active stateful connections between primary and backup.

### Group 3: Failsafe & Safe Rollbacks
**Focus:** Prevent permanent lockouts from bad network configurations.
**Tasks:**
1. Design and implement a rollback mechanism (e.g., a custom systemd service or an extension to existing tooling like `comin`).
2. The logic should activate post-deployment, wait for a success signal (e.g., external ping or internal node confirmation), and automatically trigger `nixos-rebuild switch --rollback` if the timeout is reached.
3. Ensure this mechanism integrates cleanly with the `masthead` module.

### Group 4: Metrics, Monitoring, & Telemetry
**Focus:** Extend the existing observability stack to capture router-specific data.
**Tasks:**
1. Ensure `prometheus-node-exporter` is collecting all relevant network interface metrics.
2. Deploy exporters for HA and routing specific services: `keepalived-exporter`, multi-WAN health check statuses, and DHCP metrics (e.g., `kea-exporter`).
3. Export firewall/conntrack statistics.
4. Create Grafana dashboard JSON models for HA status, WAN failover events, load balancing distribution, and per-VLAN bandwidth utilization.

### Group 5: OpenWrt Migration Agent
**Focus:** Automate the translation of legacy OpenWrt configurations to declarative Nix.
**Tasks:**
1. **Phase 1 (Parse & Plan):** Write a Python utility in `packages/openwrt-migrator/` to parse `/etc/config/network`, `dhcp`, `firewall`, `mwan3` (if present), and `wireless` from OpenWrt backups. Output an intermediate structured format (JSON/YAML).
2. **Phase 2 (Generate):** Write a generation script that reads the intermediate state and produces a valid Nix module (`openwrt-migrated.nix`) compatible with the `masthead` structure.

### Group 6: Testing Framework (NixOS VMs)
**Focus:** Create reproducible, isolated tests for the HA routing and Multi-WAN logic.
**Tasks:**
1. Develop a NixOS integration test under a new directory `tests/router-ha/`.
2. Spin up a simulated network containing: 2 Router VMs (Primary/Backup), 2 simulated ISP gateways (for Multi-WAN), and 2 Client VMs on different subnets.
3. Write Python test scripts within `nixosTest` to verify:
    - Clients successfully acquire IPs via DHCP.
    - Traffic is correctly load-balanced across multiple WAN links.
    - Traffic routes correctly through the VIP.
    - Failover scenarios:
      - (a) Disconnect ISP1, verify traffic shifts to ISP2.
      - (b) Intentionally crash the Primary Router, verify the Backup assumes the VIP, Spoofed MAC, and restores client connectivity to active ISPs within expected time constraints.

### Group 7 (Stretch Goal): NPU AI Network Analysis
**Focus:** Leverage the Rockchip RK3588 NPU for local traffic analysis using mainline Linux kernel features.
**Tasks:**
1. Configure NixOS to use the recently upstreamed open-source `rocket` driver and `mesa` for NPU support (avoiding the proprietary RKNN toolkit as we run mainline kernels).
2. Configure a port mirror or NFLOG target to forward traffic headers to a local analysis service.
3. Deploy a lightweight, locally run AI model (e.g., anomaly detection or Deep Packet Inspection) utilizing the NPU, feeding identified events into the centralized monitoring stack.

### Group 8 (Stretch Goal): Dynamic QoS & Metered WAN Traffic Shaping
**Focus:** Implement priority balancing and throttling based on the active WAN interface's link properties.
**Tasks:**
1. Design a configuration schema mapping specific subnets/MACs to priority tiers (e.g., `Critical`, `Standard`, `Throttled`, `Blocked`).
2. Create `tc` (Traffic Control) or `nftables` QoS rules to enforce these tiers.
3. Develop a script or daemon that dynamically updates these QoS rules based on the currently active WAN. When failing over to a metered connection (e.g., Starlink), automatically clamp bandwidth for non-essential subnets (like homelab servers) and prioritize the critical "work" subnet.
4. Integrate testing for these QoS tiers into the `tests/router-ha/` framework, simulating a metered failover and verifying bandwidth limits between test clients.

## Proposed File Structure
- `modules/nixos/hosts/masthead/` -> Core router configurations, VRRP definitions, Multi-WAN logic, QoS logic, role logic.
- `modules/nixos/services/router-failsafe/` -> Configuration and scripts for auto-rollback.
- `packages/openwrt-migrator/` -> Python scripts for OpenWrt config translation.
- `tests/router-ha/` -> NixOS VM Tests for routing, Multi-WAN, QoS, and failover verification.
