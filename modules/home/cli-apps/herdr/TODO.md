# herdr module backlog

## Plugin management

`herdr plugin install <name>` downloads a prebuilt binary from GitHub Releases
and places it in herdr's plugin directory. Fully compatible with Nix FOD
(fixed-output derivation) approach — `pkgs.fetchurl` with pinned hash.

### Approach for each plugin

```nix
pkgs.fetchurl {
  url = "https://github.com/nikok6/herdr-mirror/releases/download/v0.1.7/herdr-mirror-linux-x86_64";
  hash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
};
```

Then copy to herdr's plugin directory (run `herdr plugin install` once to find
the path, then replicate with Nix).

### Release formats

**herdr-mirror** (Rust, prebuilt binary):
- `herdr-mirror-linux-x86_64` — single binary, no deps
- `herdr-mirror-linux-aarch64`
- SHA256SUMS available for verification

**herdr-remote** (mixed Rust/Python):
- Primarily a macOS app (Herdi.app) with a Python relay component
- Has `herdr-push` sub-plugin for remote monitoring
- Need to investigate the relay + TUI Python deps

### Plugin configuration

Plugins are configured via TOML files in `~/.config/herdr/plugins/config/`. For
herdr-mirror this is `mirror/hosts.toml`. We can generate these via Nix's
`home.file`.

herdr supports plugins via Zellij's WASM plugin system. Plugins are compiled to
`.wasm` files and loaded at runtime.

### Community plugins identified:

| Plugin | Language | Description |
|--------|----------|-------------|
| [**herdr-mirror**](https://github.com/nikok6/herdr-mirror) | Rust | Mirror remote herdr server workspaces/agents into local sidebar |
| [**herdr-remote**](https://github.com/dcolinmorgan/herdr-remote) | Rust/JS | Remote herdr server integration |

### Key questions:

1. **How does herdr load plugins?** Config file? CLI flags? Automatic discovery?
2. **How do Zellij WASM plugins work with Nix?** Need to compile Rust → WASM in build
3. **Does herdr have a flake/nix module already** that handles plugin installation?
4. **Can plugins be Nixified** using `pkgs.buildRustPackage` or similar?
5. **Is there a herdr plugin registry** or do you configure them in `config.kdl`?

### Nix approach needed:

Similar to pi packages — we need a way to declare plugins in Nix config:

```nix
projectinitiative.cli-apps.herdr.plugins = {
  herdr-mirror = {
    enable = true;
    source = pkgs.rustPlatform.buildRustPackage { ... };
  };
};
```

Or if herdr handles plugins at runtime, we may just need to compile and symlink
the `.wasm` files to the right directory.
