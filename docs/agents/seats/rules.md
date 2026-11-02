# Seat rules

What every seat follows, Codex or Claude. A brief points here rather than copying it, and adds only
its own result and files.

- Read `/Users/canmi/workspace/AGENTS.md` and [implementer.md](implementer.md) first.
- Type no jj or git yourself. Do not run `mise env`, `printenv`, `sops` or `exec-env`, and read no
  secrets file.
- **While you write, check your own work by `mise run //:lane check <part> ...` from inside your lane**,
  and `mise run built <block>`: the parts are `Delegation.seatParts`, format, names, wire, compile and
  tests, each named for what it catches, [checking.md](../checking.md). A whole repository's check is
  the landing's.
- **An interface inside your own files is yours to change.** Stop for an interface only where it lies
  outside them, and say what you would change.
- **A long command starts by `mise run //:job start --by <your lane> -- <command>`**, anything that may
  pass about 15 seconds, and is followed by `mise run //:watch <id>` under Monitor, or read by `mise run
  //:job read <id>`, [runs.md](../runs.md). Never wait in a foreground loop, bounded or not.
- **A seat never ends its turn to wait for a background job's notice**; no notice wakes it.
- Any process you start for load or as a helper, you stop before you report, and you say so. **Kill
  only by a pid you recorded**: `cmd & P=$!` then `kill $P`, or `mise run //:job stop <id> --by <your lane>`, your own jobs alone;
  killing by name is refused, `kill-by-recorded-pid`.
- Tests that write files use their own temporary directory, removed with `Node.rmSync`.
- What you made yourself, scratch files, temp output, test leftovers, build output, you remove with
  `rm`; `trash` is only for what you did not make. An `rm` never takes a bare variable path: write a
  literal path, or `"${S:?}"/name`.
- English only, American spelling, no emoji. Comments one or two plain lines, no colon or dash in
  their prose, within 100 columns. Keep every directory within `Layout.widest` entries.
- Before you report, run `mise run //:lane handed <your lane>` from your lane and fix every finding it
  names.
- If a hook refuses you: when right, correct and go on; when wrong, report it and do not work around
  it; refused twice by one hook, report its message and how it should change. A lane refused as stale
  is reported at once: you are on an old tree.
- Report: files changed, commands run with counts, what you did not exercise, and any edit you
  propose outside your lane.
