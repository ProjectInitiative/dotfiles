#!/usr/bin/env python3

import socket
import struct
import sys
import logging
import time

try:
    import torch
    import torch.nn as nn
    TORCH_AVAILABLE = True
except ImportError:
    TORCH_AVAILABLE = False
    logging.warning("torch module not found. Model inference will be skipped or mocked if not installed.")

try:
    from prometheus_client import start_http_server, Counter
    PROMETHEUS_AVAILABLE = True
except ImportError:
    PROMETHEUS_AVAILABLE = False
    logging.warning("prometheus_client module not found. Metrics will not be exported.")

logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')

AF_NETLINK = 16
NETLINK_NETFILTER = 12

if PROMETHEUS_AVAILABLE:
    # Define Prometheus metrics
    packets_processed_total = Counter('packets_processed_total', 'Total number of packets processed by NPU analyzer')
    anomalies_detected_total = Counter('anomalies_detected_total', 'Total number of anomalous packets detected')

if TORCH_AVAILABLE:
    class LightweightAnomalyDetector(nn.Module):
        def __init__(self, input_size=100, hidden_size=64, output_size=1):
            super(LightweightAnomalyDetector, self).__init__()
            self.fc1 = nn.Linear(input_size, hidden_size)
            self.relu1 = nn.ReLU()
            self.fc2 = nn.Linear(hidden_size, hidden_size)
            self.relu2 = nn.ReLU()
            self.fc3 = nn.Linear(hidden_size, output_size)
            self.sigmoid = nn.Sigmoid()

        def forward(self, x):
            out = self.fc1(x)
            out = self.relu1(out)
            out = self.fc2(out)
            out = self.relu2(out)
            out = self.fc3(out)
            out = self.sigmoid(out)
            return out
else:
    class LightweightAnomalyDetector:
        def __init__(self, *args, **kwargs):
            pass
        def __call__(self, x):
            class MockTensor:
                def item(self):
                    return 0.1
            return MockTensor()
        def eval(self):
            pass

def create_netlink_socket():
    try:
        sock = socket.socket(AF_NETLINK, socket.SOCK_RAW, NETLINK_NETFILTER)
        sock.bind((0, 0))
        logging.info("Successfully created AF_NETLINK socket.")
        return sock
    except PermissionError:
        logging.warning("Permission denied creating AF_NETLINK socket. Are you root?")
        return None
    except Exception as e:
        logging.error(f"Error creating socket: {e}")
        return None

def main():
    if PROMETHEUS_AVAILABLE:
        start_http_server(9091)
        logging.info("Started Prometheus metrics server on port 9091")

    sock = create_netlink_socket()
    if not sock:
        logging.info("Falling back to a mock packet generator for testing...")

    model = LightweightAnomalyDetector()
    if TORCH_AVAILABLE:
        model.eval()

    try:
        while True:
            packet_len = 0
            if sock:
                try:
                    data = sock.recv(4096)
                    packet_len = len(data)
                    logging.debug(f"Received netlink packet of length {packet_len}")
                    if TORCH_AVAILABLE:
                        features = torch.zeros(1, 100)
                        features[0, 0] = float(packet_len)
                    else:
                        features = None
                except Exception as e:
                    logging.error(f"Error receiving from socket: {e}")
                    time.sleep(1)
                    continue
            else:
                packet_len = 64
                logging.debug("Mock received packet")
                if TORCH_AVAILABLE:
                    features = torch.zeros(1, 100)
                    features[0, 0] = float(packet_len)
                else:
                    features = None
                time.sleep(1)

            if PROMETHEUS_AVAILABLE:
                packets_processed_total.inc()

            if TORCH_AVAILABLE:
                with torch.no_grad():
                    output = model(features)
                    anomaly_score = output.item()
            else:
                anomaly_score = model(features).item()

            is_anomaly = anomaly_score > 0.5
            if is_anomaly:
                if PROMETHEUS_AVAILABLE:
                    anomalies_detected_total.inc()
                logging.info(f"Anomaly detected! Score: {anomaly_score:.4f}, Packet Length: {packet_len}")
            else:
                logging.debug(f"Packet normal. Score: {anomaly_score:.4f}")

    except KeyboardInterrupt:
        logging.info("Exiting...")

if __name__ == "__main__":
    main()
