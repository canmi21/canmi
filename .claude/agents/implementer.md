---
name: implementer
description: Writes one block's directory in a lane of its own, spawned by the integrator
disallowedTools: Agent, SendMessage, Workflow, Artifact
hooks:
  PreToolUse:
    - matcher: "^Bash$"
      hooks:
        - type: command
          command: "d=$(jj workspace root 2>/dev/null || pwd); while [ ! -f \"$d/hooks/agent_commands.res\" ] && [ \"$d\" != / ]; do d=$(dirname \"$d\"); done; [ -f \"$d/hooks/agent_commands.res\" ] || exit 0; e=\"$d/hooks/agent_commands.res.mjs\"; r=\"$d/node_modules/.bin/rescript\"; [ -f \"$e\" ] || { \"$r\" build >&2; [ -f \"$e\" ] || { \"$r\" clean >&2; \"$r\" build >&2; }; }; [ -f \"$e\" ] || { echo \"hooks: $e is not built and building did not make it; run mise run build in $d\" >&2; exit 1; }; exec node \"$e\" implementer"
          timeout: 120
    - matcher: "^(Edit|Write|MultiEdit|NotebookEdit)$"
      hooks:
        - type: command
          command: "d=$(jj workspace root 2>/dev/null || pwd); while [ ! -f \"$d/hooks/agent_commands.res\" ] && [ \"$d\" != / ]; do d=$(dirname \"$d\"); done; [ -f \"$d/hooks/agent_commands.res\" ] || exit 0; e=\"$d/hooks/agent_commands.res.mjs\"; r=\"$d/node_modules/.bin/rescript\"; [ -f \"$e\" ] || { \"$r\" build >&2; [ -f \"$e\" ] || { \"$r\" clean >&2; \"$r\" build >&2; }; }; [ -f \"$e\" ] || { echo \"hooks: $e is not built and building did not make it; run mise run build in $d\" >&2; exit 1; }; exec node \"$e\" lane"
  PostToolUse:
    - matcher: "^(Edit|Write|MultiEdit)$"
      hooks:
        - type: command
          command: "d=$(jj workspace root 2>/dev/null || pwd); while [ ! -f \"$d/hooks/agent_commands.res\" ] && [ \"$d\" != / ]; do d=$(dirname \"$d\"); done; [ -f \"$d/hooks/agent_commands.res\" ] || exit 0; e=\"$d/hooks/agent_commands.res.mjs\"; r=\"$d/node_modules/.bin/rescript\"; [ -f \"$e\" ] || { \"$r\" build >&2; [ -f \"$e\" ] || { \"$r\" clean >&2; \"$r\" build >&2; }; }; [ -f \"$e\" ] || { echo \"hooks: $e is not built and building did not make it; run mise run build in $d\" >&2; exit 1; }; exec node \"$e\" format"
          timeout: 120
---

Read docs/agents/implementer.md in the workspace, and work by it.
