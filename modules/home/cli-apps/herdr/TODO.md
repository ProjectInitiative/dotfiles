# herdr module backlog

## Plugin management

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
