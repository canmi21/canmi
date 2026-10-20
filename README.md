# Nested Workspace

This repository contains the shared configuration, tooling, documentation, and conventions used across my work.

The projects themselves live under `repos/`, but they are not Git submodules and are not tracked by this repository.

In other words, the outer repository owns the workspace; the inner repositories own themselves.

```text
workspace/
├── repos/        # independent repositories, ignored here
├── model/        # the rules a program can decide, and their checks
├── docs/         # the reasoning, and the rules only judgment keeps
├── scripts/      # shared tasks, in ReScript
├── hooks/        # shared hooks
├── mise.toml     # shared tasks and toolchain
├── rustfmt.toml  # shared formatting
├── AGENTS.md     # agent instructions
└── ...
```

This gives small projects a common environment without turning them into a monorepo, while larger projects are still free to carry their own tooling, configuration, or even nested repository structure.

Everything worth explaining lives in `docs/`, and what a program can check in `model/`.

If you're curious, point an LLM at it and let it read.

## License

MIT License © 2024 [Canmi](https://canmi.net)
