import argparse
import json
import os
import sys

SCENARIOS_FILE = "/etc/infra-test/scenarios.json"
METRICS_DIR = "/var/lib/prometheus-node-exporter"

def load_scenarios():
    if not os.path.exists(SCENARIOS_FILE):
        print(f"Error: Scenarios file {SCENARIOS_FILE} not found.", file=sys.stderr)
        sys.exit(1)
    with open(SCENARIOS_FILE, 'r') as f:
        return json.load(f)

def list_scenarios():
    scenarios = load_scenarios()
    if not scenarios:
        print("No scenarios found.")
        return
    print("Available Scenarios:")
    for name, data in scenarios.items():
        print(f"  - {name}")

def trigger_scenario(name):
    scenarios = load_scenarios()
    if name not in scenarios:
        print(f"Error: Scenario '{name}' not found.", file=sys.stderr)
        sys.exit(1)

    scenario = scenarios[name]
    metric_name = scenario.get('metric')
    labels = scenario.get('labels', {})
    value = scenario.get('value')

    if not metric_name or value is None:
        print(f"Error: Invalid scenario definition for '{name}'.", file=sys.stderr)
        sys.exit(1)

    label_str = ",".join(f'{k}="{v}"' for k, v in labels.items())
    if label_str:
        metric_line = f"{metric_name}{{{label_str}}} {value}\n"
    else:
        metric_line = f"{metric_name} {value}\n"

    prom_file = os.path.join(METRICS_DIR, f"{name}.prom")

    try:
        os.makedirs(METRICS_DIR, exist_ok=True)
        with open(prom_file, 'w') as f:
            f.write(f"# HELP {metric_name} Mock metric for testing alert scenario {name}\n")
            f.write(f"# TYPE {metric_name} gauge\n")
            f.write(metric_line)
        print(f"Successfully triggered scenario '{name}'.")
        print(f"Wrote to {prom_file}:\n{metric_line}")
    except PermissionError:
        print(f"Error: Permission denied. You may need root privileges to write to {METRICS_DIR}.", file=sys.stderr)
        sys.exit(1)

def clear_scenarios():
    if not os.path.exists(METRICS_DIR):
        print("No mock metrics to clear.")
        return

    scenarios = load_scenarios()
    valid_files = [f"{name}.prom" for name in scenarios.keys()]

    cleared = 0
    try:
        for file in os.listdir(METRICS_DIR):
            if file in valid_files:
                os.remove(os.path.join(METRICS_DIR, file))
                cleared += 1
        print(f"Cleared {cleared} mock metric files.")
    except PermissionError:
        print(f"Error: Permission denied. You may need root privileges to clear metrics from {METRICS_DIR}.", file=sys.stderr)
        sys.exit(1)

def main():
    parser = argparse.ArgumentParser(description="Infra-Alert-Tester CLI")
    subparsers = parser.add_subparsers(dest='command', help='Commands')

    # List command
    subparsers.add_parser('list', help='List available test scenarios')

    # Trigger command
    trigger_parser = subparsers.add_parser('trigger', help='Trigger a test scenario')
    trigger_parser.add_argument('scenario', help='Name of the scenario to trigger')

    # Clear command
    subparsers.add_parser('clear', help='Clear all triggered scenarios')

    args = parser.parse_args()

    if args.command == 'list':
        list_scenarios()
    elif args.command == 'trigger':
        trigger_scenario(args.scenario)
    elif args.command == 'clear':
        clear_scenarios()
    else:
        parser.print_help()

if __name__ == '__main__':
    main()
