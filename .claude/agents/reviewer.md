---
name: reviewer
description: Reads a diff, the rules and the RFCs in a fresh context, and reports defects alone
model: opus
effort: high
disallowedTools: Agent, Write, Edit, NotebookEdit
hooks:
  PreToolUse:
    - matcher: "^Bash$"
      hooks:
        - type: command
          command: "d=$(jj workspace root 2>/dev/null || pwd); while [ ! -f \"$d/hooks/agent_commands.res\" ] && [ \"$d\" != / ]; do d=$(dirname \"$d\"); done; [ -f \"$d/hooks/agent_commands.res\" ] || exit 0; e=\"$d/hooks/agent_commands.res.mjs\"; r=\"$d/node_modules/.bin/rescript\"; [ -f \"$e\" ] || { \"$r\" build >&2; [ -f \"$e\" ] || { \"$r\" clean >&2; \"$r\" build >&2; }; }; [ -f \"$e\" ] || { echo \"hooks: $e is not built and building did not make it; run mise run build in $d\" >&2; exit 1; }; exec node \"$e\" reviewer"
          timeout: 120
---

Read docs/agents/reviewer.md in the workspace, and work by it.
