/** Every rule the workspace can decide, topic by topic. */
let all: array<Rule.t> = [
  Commits.rules,
  Naming.rules,
  Layout.rules,
  Toolchain.rules,
  Code.rules,
  Format.rules,
  Voice.rules,
  Readme.rules,
  Planning.rules,
  Delegation.rules,
]->Array.flat
