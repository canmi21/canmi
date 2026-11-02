# Shell

**Shell is for what one shot does, one command however many lines its flags take; what has an order,
a conditional, a loop or a retry, an orchestration, is ReScript.**

The user's interactive shell is **fish**, configured in `~/.config/fish/config.fish`.

This matters in two directions, and they are opposite:

- **A command written for the user to run** must be fish syntax. `set -gx KEY value`, not `export
  KEY=value`. Command substitution is `(cmd)`, not `$(cmd)`.
- **A command an agent runs through its own tooling** goes through that tool's shell, which on this
  machine is zsh, so it must be POSIX syntax. Writing fish syntax there fails with a parse error,
  and writing bash syntax into a fish snippet fails the same way in reverse.

Three more platform facts that cost time when forgotten. This is macOS, so `sed` is BSD sed and does
not support `\b` word boundaries -- use `perl -pi -e` for word-boundary replaces. mise activation is
directory-scoped and shell-based, so a command run from a shell without mise sees none of the pinned
versions. And **there is no `timeout`**: it is GNU coreutils, `gtimeout` is not linked either, and
[agent-protocol.md](../agents/agent-protocol.md) asks every command of unknown duration to carry a
ceiling. `perl -e 'alarm N; exec @ARGV' <command>` is the one that is always present.

### An agent stops a background process with a signal it can catch

`kill -9` on a dev server leaves its children running for as long as the machine is up. A supervisor
written in node -- `vite dev` carrying a Cloudflare platform proxy, `wrangler dev`, anything
standing on miniflare -- registers its cleanup on `exit`, `SIGINT`, `SIGTERM` and `SIGHUP`.
`SIGKILL` runs none of those, and the child runtime does not watch for its parent's death, so it is
reparented to `init` and holds its memory until something else kills it.

So a background process is stopped with `kill -TERM` or `kill -INT`, and the agent waits for it to
be gone before moving on. `-9` is for a process still there after a grace period, and reaching for
it is the decision to leak whatever it was holding.

**The signal has to reach the process that owns the child, not a wrapper above it.** A `mise run
dev-api` is a shell running a node process running `workerd`; signaling the shell ends the shell,
and what it supervises is orphaned with its exit hook unrun.

So: signal the node process by name, or the whole process group with `kill -INT -<pgid>`, and
**count what is left afterwards** rather than assuming. `ps -eo ppid | awk '$1==1'` is the check,
and it takes a second.

The same reasoning says not to go after the children instead. A supervised runtime is restarted when
it dies -- miniflare counts the crashes and says so -- so killing a child whose parent is still
alive buys nothing and hides the leak. Stop the parent, or restart it.

This is about signals an agent sends, not about how the user leaves a server: Ctrl-C in a terminal
is already `SIGINT`, and closing the window is `SIGHUP`. Both are caught.
