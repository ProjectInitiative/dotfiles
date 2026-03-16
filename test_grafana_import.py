import json
import subprocess

with open("modules/nixos/services/monitoring/default.nix", "r") as f:
    content = f.read()

print("Alert JSON configuration generation logic exists:", "scenarios.json" in content)

cmd = "nix-instantiate --eval -E 'with import <nixpkgs> {}; let config = {}; in builtins.toJSON (lib.foldl\\' (acc: rule: if rule ? testScenarios then acc // rule.testScenarios else acc) {} (lib.flatten (map (group: group.rules) (lib.flatten (map (file: (import file { inherit config lib pkgs; }).services.grafana.provision.alerting.rules.settings.groups) [ ./systems/aarch64-linux/dinghy/grafana-alerts.nix ])))))'"
try:
    result = subprocess.run(cmd, shell=True, capture_output=True, text=True)
    print("Nix eval successful:", result.returncode == 0)
    if result.returncode != 0:
        print(result.stderr)
    else:
        print("Generated JSON:", result.stdout)
except Exception as e:
    print("Failed to run nix-instantiate", e)
