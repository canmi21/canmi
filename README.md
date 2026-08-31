# Nested Workspace

This repository contains the shared configuration, tooling, documentation, and conventions used across my work.

The projects themselves live under `repos/`, but they are not Git submodules and are not tracked by this repository.

In other words, the outer repository owns the workspace; the inner repositories own themselves.

```text
workspace/
├── repos/        # independent repositories, ignored here
├── spec/         # workspace design and documentation
├── hooks/        # shared hooks
├── mise.toml     # shared tasks and toolchain
├── rustfmt.toml  # shared formatting
├── CLAUDE.md     # agent instructions
└── ...
```

This gives small projects a common environment without turning them into a monorepo, while larger projects are still free to carry their own tooling, configuration, or even nested repository structure.

Everything worth explaining lives in `spec/`.

If you're curious, point an LLM at it and let it read.

## License

MIT License © 2026 [Canmi](https://canmi.net)
