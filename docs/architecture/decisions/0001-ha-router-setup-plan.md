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
- Leverage onboard NPUs (rk3588) for AI-driven network analysis and anomaly detection using mainline Linux kernel features.
- Implement dynamic Quality of Service (QoS) and Traffic Shaping to prioritize specific hosts or subnets (e.g., a "work" VLAN) and aggressively throttle non-essential traffic (e.g., servers) when failed over to a metered WAN connection (like Starlink).

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
3. **MAC Spoofing & Scripts:** Standard VRRP VMACs can cause issues with strict ISP modems. Explicitly define that WAN MAC spoofing will be handled via `keepalived`'s `notify_master` and `notify_fault` shell scripts to dynamically rewrite the physical interface MAC on the backup node only upon promotion.
4. **State Sync:** Isolate `conntrackd` state synchronization on a dedicated sync VLAN between the primary and backup nodes to prevent broadcast storms or state manipulation on the primary LAN.
5. **Failover Topologies:** Expand the failover logic to support multiple architecture combinations rather than exclusively relying on VIP/MAC spoofing. Include support for:
    - **Administrative Link State:** Keeping the backup node's WAN ports administratively disabled until a VRRP state change triggers them to activate.
    - **Hybrid NAT/Passthrough:** A split design where the primary internet uses IP passthrough to the primary node, while a metered connection (like Starlink) leverages its built-in router to provide a double-NAT connection directly to the backup node.

### Group 3: Failsafe & Safe Rollbacks
**Focus:** Prevent permanent lockouts from bad network configurations.
**Tasks:**
1. **Push-Based Deployment Integration:** Discard local wrapper scripts and pull-based agents (like `comin`). Design the failsafe mechanism to integrate directly with a push-based deployment pipeline (tool TBD).
2. **Validation Pipeline:** The deployment workflow must push the Nix closure, activate the configuration, and execute a suite of remote validation checks (e.g., verifying gateway reachability, checking active routing tables, and confirming SSH connectivity). If these validation checks fail or time out, the deployment pipeline must automatically initiate a rollback on the target node.

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
1. **Phase 1 (Data Acquisition):** Do not build a raw text parser for `/etc/config/*`. Instead, the migration process should dictate running `ubus call uci get_all` on the existing OpenWrt device to dump the configuration as a clean JSON object.
2. **Phase 2 (Generate):** The Python script in `packages/openwrt-migrator/` will ingest that JSON directly to generate the Nix module (`openwrt-migrated.nix`) compatible with the `masthead` structure.

### Group 6: Testing Framework (NixOS VMs)
**Focus:** Create reproducible, isolated tests for the HA routing and Multi-WAN logic.
**Tasks:**
1. Develop a NixOS integration test under a new directory `tests/router-ha/`.
2. **Architecture Optimization:** To avoid severe CPU overhead during iteration, explicitly evaluate the router VMs as `x86_64-linux` for the test suite. The routing, VRRP, and multi-WAN logic is architecture-agnostic and will validate properly on the host architecture before deploying to the target ARM boards.
3. Spin up a simulated network containing: 2 Router VMs (Primary/Backup), 2 simulated ISP gateways (for Multi-WAN), and 2 Client VMs on different subnets.
4. Write Python test scripts within `nixosTest` to verify:
    - Clients successfully acquire IPs via DHCP.
    - Traffic is correctly load-balanced across multiple WAN links.
    - Traffic routes correctly through the VIP.
    - Failover scenarios:
      - (a) Disconnect ISP1, verify traffic shifts to ISP2.
      - (b) Intentionally crash the Primary Router, verify the Backup assumes the VIP, Spoofed MAC, and restores client connectivity to active ISPs within expected time constraints.

### Group 7: NPU AI Network Analysis
**Focus:** Leverage the Rockchip RK3588 NPU for local traffic analysis using mainline Linux kernel features.
**Tasks:**
1. Configure NixOS to use the recently upstreamed open-source `rocket` driver and `mesa` for NPU support (avoiding the proprietary RKNN toolkit as we run mainline kernels).
2. Configure a port mirror or NFLOG target to forward traffic headers to a local analysis service.
3. **Model Integration:** Build or adapt a lightweight PyTorch or TensorFlow model for traffic anomaly detection that successfully compiles for the `rocket`/`mesa` NPU pipeline, mirroring the approach used for local Frigate models. Feed identified events into the centralized monitoring stack.

### Group 8: Dynamic QoS & Metered WAN Traffic Shaping
**Focus:** Implement priority balancing and throttling based on the active WAN interface's link properties.
**Tasks:**
1. Design a configuration schema mapping specific subnets/MACs to priority tiers (e.g., `Critical`, `Standard`, `Throttled`, `Blocked`).
2. Create `tc` (Traffic Control) or `nftables` QoS rules to enforce these tiers.
3. **QoS Triggers:** Tie the dynamic QoS and `nftables` traffic shaping directly into the `keepalived` state change scripts (`notify_master`/`notify_fault`). This ensures the metered/Starlink throttling profile applies instantly upon failover, without waiting for a polling daemon to notice the WAN shift. When failing over to a metered connection, automatically clamp bandwidth for non-essential subnets and prioritize the critical "work" subnet.
4. Integrate testing for these QoS tiers into the `tests/router-ha/` framework, simulating a metered failover and verifying bandwidth limits between test clients.

## Proposed File Structure
- `modules/nixos/hosts/masthead/` -> Core router configurations, VRRP definitions, Multi-WAN logic, QoS logic, role logic.
- `modules/nixos/services/router-failsafe/` -> Configuration and scripts for auto-rollback.
- `packages/openwrt-migrator/` -> Python scripts for OpenWrt config translation.
- `tests/router-ha/` -> NixOS VM Tests for routing, Multi-WAN, QoS, and failover verification.
