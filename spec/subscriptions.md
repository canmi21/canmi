# Serving a vendor's subscription

A subscription is a vendor's plan for one person -- Claude Pro or Max, SuperGrok, ChatGPT -- as
opposed to an API key billed per token. A program here may serve one as an API only the way its
vendor lets a third party use it, and vendors differ: one allows its own client and nothing else,
another opens its plan to other agents. So the rule is per vendor, each entry with its source and
the date it was read, since these terms have moved more than once in a year.

## Anthropic: through Claude Code, and as Claude Code

A Claude subscription's OAuth sign-in is for Claude Code and claude.ai alone; Anthropic's legal and
compliance terms for Claude Code say so from 2026-02-19, and from 2026-04-04 a third-party harness
on a subscription is billed as extra usage rather than against the plan. Anthropic tells the two
apart by what a request says, not only by its credential: another agent's system prompt on the
same token is taken for third-party traffic.

So a Claude subscription is served by driving the genuine `claude` binary, never by sending its
token over HTTP, and the binary keeps its own system prompt: the caller's instructions go into the
conversation, not in place of Claude Code's. magpie's Claude bridge
(`yetone/magpie`, `internal/gateway/claude_subscription.go`) is built this way and says why; it is
the reference to follow.

Read 2026-10-09. Sources: Anthropic's Claude Code legal and compliance page; magpie's
`docs/reference.md`, "Signed-in agents as providers".

## xAI: open to other agents

xAI announced on 2026-05-21 that a SuperGrok or X Premium subscription may be used inside OpenCode,
signed in with OAuth from OpenCode itself, and that more open-source agents are to follow
(<https://x.ai/news/grok-opencode>). A Grok subscription may therefore be called directly with its
OAuth sign-in at the backend Grok's own CLI uses -- OpenAI's Responses API at
`cli-chat-proxy.grok.com` -- as magpie's Grok plugin does (`magpie-community/plugins`,
`packages/grok`). That plugin borrows the Grok Build CLI's sign-in rather than OpenCode's, which is
the same kind of use and not the one xAI named.

Driving the CLI stays allowed as well. Which of the two a project uses is that project's call, made
on what it costs to keep running, not on these terms: platform's grok drives the CLI for that
reason (`repos/platform/spec/architecture/grok/bridge.md`).

Read 2026-10-09.

## Any other vendor

Its terms are read before its subscription is served, and an entry is added here: what it allows a
third party, where that is written, and when it was read. Until then it is served only through
its own client, as Anthropic's is.
