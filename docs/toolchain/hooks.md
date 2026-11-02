# Hooks

### Hooks are ReScript too, and a hook that cannot start says so

`hooks/` holds the policies once, in ReScript like every script here, and both vendor directories
bind the same `hooks/run.res` entrypoint; `.claude/settings.json` and `.codex/hooks.json` are only
the glue that exposes it to each harness.

**The failure mode is what the adapter is written against.** A hook is launched by the harness
rather than by an interactive shell, and one that fails to start enforces nothing while looking
exactly like one that passed -- silent non-enforcement is worse than none, because it is believed.
So the adapter line builds the entrypoint when its compiled output is missing, cleans and builds
again when an incremental build leaves it missing, and otherwise exits 1 with the reason on stderr:
never a quiet 0 over a hook that did not run. It runs `node` from the harness's PATH and `rescript`
from the workspace's `node_modules`, so a fresh clone needs `pnpm install` first.

Compatibility is a check, not a claim made once: `check workspace scripts` runs the entrypoint with
representative Claude Code and Codex payloads, and the adapter line itself through `sh`, from a
subdirectory, from inside a nested repository and from outside any.

**`hooks/bin/rm` and its guard stay Python, under `/usr/bin/python3`.** It is a command an agent
types, first on PATH, not a hook: it has to answer before anything is built, in whatever shell the
agent has, and macOS's own Python is the one interpreter always there. `Toolchain.kept` names it,
and `check workspace hooks` runs its tests.
