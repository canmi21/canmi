# Toolchain

- [Shell](toolchain/shell.md)
- [Deletion](toolchain/deletion.md)
- [Secrets](toolchain/secrets.md)
- [Version control](toolchain/jj.md)
- [Versions](toolchain/versions.md)
- [Hooks](toolchain/hooks.md)
- [Application tooling](toolchain/runtime.md)
- [Dependencies](toolchain/dependencies.md)
- [Caches](toolchain/clean.md)
- [CI dependencies](toolchain/ci.md)
- [Releases](toolchain/releases.md)
- [Scripts and CLIs](toolchain/scripts.md)

## Addresses

Local development is `localhost`. Every URL typed, configured or written down for a service running
on this machine uses that name, at every layer: the browser, the config file, the health check, the
test fixture. The words part refuses a literal loopback address in this repository.

A literal IP is what a machine on the local network is reached by, and only that. `localhost` on
another device is that device, so an address handed across the network has to name a host rather
than a role. Whichever form the network offers -- the address itself or a name that resolves to it
-- is the one to use.

Public addresses are decided case by case. There is no default worth writing down for them.

A listen address is not an address in this sense. What a server binds to answers which interfaces it
accepts on, and `0.0.0.0` or `::` there is a different question with a different answer.

## Default stacks

| Area                      | Stack                      |
| ------------------------- | -------------------------- |
| Binaries and applications | Rust + Cargo               |
| Web                       | TypeScript + pnpm + Svelte |
| Scripts and tasks         | ReScript                   |

These are defaults, not a whitelist. Reaching outside them is a structural decision and belongs to
the user -- see [agent-protocol.md](agents/agent-protocol.md).
