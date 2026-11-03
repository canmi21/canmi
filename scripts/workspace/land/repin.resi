/***
 * A repository's pin of its sibling, `[versions] pin`, moved to the sibling's `main@origin` as it
 * lands, so CI builds the commit the landing was checked against, docs/commits.md. The model's
 * interface, `docs/code.md`.
 */

/** The text with the commit `repository`'s `ref:` line pins replaced by `commit`, the rest kept. */
let repinned: (string, ~repository: string, ~commit: string) => string

/**
 * The pin under `root` moved to its sibling's `main@origin`: none where `root` pins nothing or the
 * pin is there already, else the commit moved from, the one moved to and the pin's path relative
 * to `root`, the file rewritten; why where the pin names no commit or the sibling cannot be read.
 */
let moved: (~root: string) => result<option<(string, string, string)>, string>
