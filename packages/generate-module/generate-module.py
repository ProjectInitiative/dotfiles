#!/usr/bin/env python3

import os
import sys
import argparse
from pathlib import Path

def create_module_template(package_name: str, module_type: str = "apps") -> str:
    """Generate the Nix module template content."""
    return f'''{{
  options,
  config,
  lib,
  pkgs,
  namespace,
  ...
}}:
with lib;
with lib.${{namespace}};
let
  cfg = config.${{namespace}}.{module_type}.{package_name};
in
{{
  options.${{namespace}}.{module_type}.{package_name} = with types; {{
    enable = mkBoolOpt false "Whether or not to enable {package_name}.";
  }};

  config = mkIf cfg.enable {{
    environment.systemPackages = with pkgs; [ {package_name} ];
  }};
}}
'''

def generate_module(package_name: str, base_path: str = "modules/nixos", module_type: str = "apps") -> None:
    """Generate a new NixOS module for the specified package."""
    # Create the full path for the module
    module_path = Path(base_path) / module_type / package_name
    module_file = module_path / "default.nix"

    # Create directories if they don't exist
    module_path.mkdir(parents=True, exist_ok=True)

    # Generate the module content
    content = create_module_template(package_name, module_type)

    # Write the module file
    with open(module_file, 'w') as f:
        f.write(content)

    print(f"Created module at: {module_file}")
    print(f"\nTo use this module, add the following to your configuration:")
    print(f"{{\n  {namespace}.{module_type}.{package_name}.enable = true;\n}}")

def main():
    parser = argparse.ArgumentParser(description='Generate NixOS module templates')
    parser.add_argument('package_name', help='Name of the package to create a module for')
    parser.add_argument('--type', default='apps', help='Module type (default: apps)')
    parser.add_argument('--path', default='modules/nixos', help='Base path for modules (default: modules/nixos)')
    parser.add_argument('--namespace', default='plusultra', help='Namespace for the module (default: plusultra)')

    args = parser.parse_args()

    # Store namespace globally for use in the success message
    global namespace
    namespace = args.namespace

    try:
        generate_module(args.package_name, args.path, args.type)
    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)

if __name__ == "__main__":
    main()
