# Caches

### A cache is what a tool can write again, and nothing else is

`mise run clean` runs every repository's own `clean`, or one named repository's. What each removes
is the repository's to say, because a cache belongs to the tool that writes it and a repository is
what chose its tools. The line every one of them draws is the same, and it is what makes `clean`
safe to run without thinking first:

- **Dependencies are not caches.** `node_modules` stays exactly as installed and only what tools
  dropped inside it goes -- `.vite`, `.vite-temp`, `.cache`, `.vitest`. A clean that ends in a
  reinstall is not a clean, it is a network bill. The same holds for `~/.cargo/registry` and
  `~/.cargo/git`, and pnpm's store is the machine's rather than any repository's, so no `clean`
  prunes it.
- **Local state is not a cache.** `.wrangler/state` is a local D1, KV and R2 emulation -- rows
  somebody typed, not output somebody built -- so only `.wrangler/tmp` goes.
- **cargo owns its own output.** `cargo clean` is what empties the target directory. `[build]
  target-dir` can move it anywhere, so a sweep matching the word `target` would miss the real one
  and find somebody else's. A test may leave a directory read-only under `CARGO_TARGET_TMPDIR`, as
  the platform's container driver does for a secret's, which stops `cargo clean`, so `clean` makes
  that directory writable first.
- **ReScript's output goes as well.** Each `lib/` beside a `rescript.json` and every `*.res.mjs`
  compiled in place is removed, since every task builds them again before it runs. The workspace's
  own `clean` takes its own and leaves `repos/` to each repository's.

**What gets removed is decided twice, by a name and by version control.** A path a `clean` sweeps
has to be one its tools write _and_ be ignored by the repository _and_ have nothing tracked
underneath it. Neither half is enough on its own: web ignores `build/` and tracks four records under
`data/build/` that a site-only CI job cannot regenerate, so a name alone would delete them -- while
"everything git ignores" is `node_modules`, `.env`, a photograph library and that local database.
**A sweep stops at every repository boundary that is not its own**: a directory carrying a `.git` or
a `.jj` is somebody else's to clean.
