# File: mcp-proxy-runner/default.nix
{
  # This makes the file self-contained and buildable directly.
  pkgs ? import <nixpkgs> { }
}:

let
  # --- Part 1: Build the underlying Node.js application ---
  # This part remains mostly the same, as it's a dependency for our script.

  packageLockFile = ./package-lock.json;

  mcpProxyApp = pkgs.buildNpmPackage rec {
    pname = "mcp-superassistant-proxy";
    version = "0.0.11";

    src = pkgs.fetchurl {
      url = "https://registry.npmjs.org/@srbhptl39/mcp-superassistant-proxy/-/mcp-superassistant-proxy-${version}.tgz";
      hash = "sha256-jxe4Etzoj9cCYhZQ8iwL7mE+l4LYu4Rpih4Scfnq8yw=";
    };

    npmDepsHash = "sha256-90jXvsqecMvPBgsxmMuSmEIGUVN2KHnbzlI4kWXadoc=";

    postPatch = ''
      cp ${packageLockFile} ./package-lock.json
    '';

    NODE_OPTIONS = "--openssl-legacy-provider";

    # Meta information is now moved to the final derivation below.
  };

in
# --- Part 2: Create a self-contained, runnable script ---
# This approach creates a final script and directly substitutes the full path
# to the executable, avoiding any PATH lookup issues.
pkgs.writeShellScriptBin "mcp-proxy-start" ''
  #!${pkgs.bash}/bin/bash
  set -e

  DEFAULT_CONFIG_PATH="$HOME/dotfiles/homes/dotfiles/mcpconfig.json"
  CONFIG_PATH="''${1:-$DEFAULT_CONFIG_PATH}"

  if [ ! -f "$CONFIG_PATH" ]; then
    echo "Error: MCP configuration file not found at '$CONFIG_PATH'"
    echo "Please create it or provide a different path as an argument."
    exit 1
  fi

  echo "--> Starting MCP SuperAssistant Proxy (self-contained)..."
  echo "--> Using config file: $CONFIG_PATH"
  echo "--> Press Ctrl+C to stop the server."
  echo ""

  # Execute the proxy using its full, absolute path from the Nix store.
  # This is the most robust method as it doesn't rely on PATH.
  # We also add nodejs to the path, as the proxy script itself may need it.
  export PATH="${pkgs.nodejs}/bin:$PATH"
  exec "${mcpProxyApp}/bin/@srbhptl39/mcp-superassistant-proxy" --config "$CONFIG_PATH"
''
