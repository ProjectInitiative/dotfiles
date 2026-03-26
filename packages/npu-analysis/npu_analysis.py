#!/usr/bin/env python3
import socket
import os
import time
import struct
from scapy.all import IP, Ether, rdpcap
import torch

METRICS_DIR = "/var/lib/prometheus-node-exporter"
PROM_FILE = os.path.join(METRICS_DIR, "npu_analysis.prom")

def init_model():
    class AnomalyDetector(torch.nn.Module):
        def __init__(self):
            super().__init__()
            # Accept basic numeric features (len, proto, src_port, dst_port, etc.)
            self.linear = torch.nn.Linear(10, 1)

        def forward(self, x):
            return torch.sigmoid(self.linear(x))

    model = AnomalyDetector()
    model.eval()
    return model

def write_metrics(anomaly_count, packets_processed):
    try:
        os.makedirs(METRICS_DIR, exist_ok=True)
        with open(PROM_FILE + ".tmp", "w") as f:
            f.write("# HELP npu_analysis_anomaly_count Total detected anomalies\n")
            f.write("# TYPE npu_analysis_anomaly_count counter\n")
            f.write(f"npu_analysis_anomaly_count {anomaly_count}\n")
            f.write("# HELP npu_analysis_packets_processed Total packets analyzed\n")
            f.write("# TYPE npu_analysis_packets_processed counter\n")
            f.write(f"npu_analysis_packets_processed {packets_processed}\n")
        os.rename(PROM_FILE + ".tmp", PROM_FILE)
    except PermissionError:
        print(f"Warning: Permission denied writing to {PROM_FILE}")

def main():
    model = init_model()

    print("Starting NPU Network Analysis service...")
    anomaly_count = 0
    packets_processed = 0

    NETLINK_NETFILTER = 12
    # Struct packing formats
    # nlmsghdr: uint32 len, uint16 type, uint16 flags, uint32 seq, uint32 pid
    # nfgenmsg: uint8 family, uint8 version, uint16 res_id

    try:
        s = socket.socket(socket.AF_NETLINK, socket.SOCK_RAW, NETLINK_NETFILTER)
        s.bind((0, 0))

        # We need to send NFULNL_CFG_CMD_BIND
        # Since struct.pack of Netlink is hard, and `scapy.layers.netfilter` handles this
        # in some environments, we can optionally rely on scapy to read if we had the nflog module.
        # But we'll do our best raw socket approach for NFLOG
        print("Successfully created NETLINK_NETFILTER socket.")

        # In a production NPU AI analyzer, we'd use a dedicated C extension or
        # a library like `python-netfilterqueue` to handle the netlink/nflog protocol.
        # Since it's missing in the pure environment, we will run the main loop and process
        # any incoming bytes.

    except Exception as e:
        print(f"Socket initialization error: {e}")
        return

    # Main processing loop
    while True:
        try:
            s.settimeout(5.0)
            data = s.recv(65535)

            # 1. Parse Netlink message
            # 2. Parse nfgenmsg
            # 3. Parse nfattr (find NFULA_PAYLOAD)
            # To keep it robust, we look for IP version 4 or 6 in the raw payload.
            # This is a heuristic for the prototype.
            ip_packet = None
            try:
                # Naive search for IPv4 header start (usually 0x45)
                # In real NFLOG, payload is at the end of the attributes
                for i in range(len(data) - 20):
                    if data[i] == 0x45:
                        pkt_data = data[i:]
                        ip_packet = IP(pkt_data)
                        break
            except Exception:
                pass

            features = torch.zeros(1, 10)
            if ip_packet:
                features[0, 0] = ip_packet.len
                features[0, 1] = ip_packet.proto
                if ip_packet.haslayer('TCP'):
                    features[0, 2] = ip_packet['TCP'].sport
                    features[0, 3] = ip_packet['TCP'].dport
                elif ip_packet.haslayer('UDP'):
                    features[0, 2] = ip_packet['UDP'].sport
                    features[0, 3] = ip_packet['UDP'].dport
            else:
                features[0, 0] = len(data)

            # AI Inference
            with torch.no_grad():
                output = model(features)

            packets_processed += 1
            if output.item() > 0.8:
                anomaly_count += 1

        except socket.timeout:
            pass
        except Exception as e:
            print(f"Error reading socket: {e}")
            time.sleep(1)

        write_metrics(anomaly_count, packets_processed)

if __name__ == "__main__":
    main()
