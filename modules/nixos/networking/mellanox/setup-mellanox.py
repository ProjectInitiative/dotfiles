#!/usr/bin/env python3

# importing the module
import json
import subprocess
import argparse


def main():

    parser = argparse.ArgumentParser(description='Configure Mellanox network cards')
    parser.add_argument('--config', '-c', 
        help='Path to JSON configuration file (default: /etc/mellanox/mellanox-interfaces.json)',
        default='/etc/mellanox/mellanox-interfaces.json')
    args = parser.parse_args()

    # Opening JSON file
    with open(args.config) as json_file:
        # with open('./templates/example-mellanox-interfaces.json') as json_file:
        data = json.load(json_file)

        for interface in data["interfaces"]:
            mellanox_card_path = "".join(
                ["/sys/bus/pci/devices/", interface["pci_address"], "/mlx4_port"]
            ).replace(":", "\:")
            for mlnx_port in interface["mlnx_ports"]:
                full_port_path = "".join([mellanox_card_path, mlnx_port])
                print(
                    "".join(["change ", full_port_path, " mode to ", interface["mode"]])
                )
                try:
                    subprocess.call(
                        [" ".join(["echo", interface["mode"], ">", full_port_path])],
                        shell=True,
                    )
                    # with open(full_port_path, 'w') as f:
                    #     f.write(interface['mode'])
                except:
                    print("".join(["could not write to", full_port_path]))
            for nic in interface["nics"]:
                try:
                    subprocess.call(
                        ["".join(["ifup ", nic, " --force"])], shell=True
                    )
                except:
                    print("".join(["could not activate ", nic]))
            print(interface)


if __name__ == "__main__":
    main()
