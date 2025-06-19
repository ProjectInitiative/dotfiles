{
  pkgs ? import <nixpkgs> { },
}:

pkgs.stdenv.mkDerivation rec {
  pname = "mcp-superassistant-proxy-runner";
  version = "1.0.0";

  # We don't have source files, as we're generating the script directly.
  # An empty src is needed to satisfy mkDerivation.
  src = pkgs.lib.cleanSource ./.;

  # Runtime dependencies: The commands our script needs to be able to call.
  # The proxy needs npx and may need docker depending on your config.
  # These will be available in the PATH when the final script runs.
  propagatedBuildInputs = [
    pkgs.nodejs # Provides npx
    pkgs.docker # Provides docker, in case your config uses it
  ];

  # The install phase creates our runnable script.
  installPhase = ''
    runHook preInstall

    install -d $out/bin

    # Create the 'mcp-proxy-start' command script using a "here document".
    # This is a clean way to write multi-line strings in shell.
    cat > $out/bin/mcp-proxy-start << EOF
    #!${pkgs.stdenv.shell}
    #
    # This script starts the MCP SuperAssistant proxy server.
    # It requires a configuration file at:
    #   /etc/nixos/mcp/mcpconfig.json
    #
    # This file's path is hardcoded into the command below.
    #

    CONFIG_PATH="/etc/nixos/mcp/mcpconfig.json"

    # Check if the config file exists before trying to run.
    if [ ! -f "\$CONFIG_PATH" ]; then
      echo "Error: MCP configuration file not found at \$CONFIG_PATH"
      echo "Please create it before running this command."
      exit 1
    fi

    echo "--> Starting MCP SuperAssistant Proxy..."
    echo "--> Using config file: \$CONFIG_PATH"
    echo "--> Press Ctrl+C to stop the server at any time."
    echo ""

    # 'exec' replaces the shell process with the npx process.
    # This is good practice for cleaner signal handling (like Ctrl+C).
    exec npx @srbhptl39/mcp-superassistant-proxy@latest --config "\$CONFIG_PATH"

    EOF

    # Make our new script executable.
    chmod +x $out/bin/mcp-proxy-start

    runHook postInstall
  '';

  meta = with pkgs.lib; {
    description = "A manual command-line runner for the MCP SuperAssistant Proxy";
    homepage = "https://github.com/srbhptl39/mcp-superassistant-proxy";
    license = licenses.mit;
    platforms = platforms.all;
    maintainers = [ ]; # Add your handle if you like
  };
}
