/***
 * What a change touches in a repository, so its check runs those blocks alone,
 * docs/agents/checking.md. The model's interface, `docs/code.md`.
 */

/** Every block, or the blocks named, each by its package's name. */
type touched =
  | Every
  | Blocks(array<string>)

/**
 * The blocks the changed paths touch, each block by its name and directory relative to the
 * repository. A path in no block's directory is shared, so it touches every block, as `full` does.
 */
let of_: (~paths: array<string>, ~blocks: array<(string, string)>, ~full: bool) => touched

/** The changed paths of a repository's working copy and its commits not yet at its origin. */
let changed: string => array<string>

/** Each package under a repository's `code/`, by its name less its scope, and its directory. */
let blocksOf: string => array<(string, string)>

/**
 * What a repository's verify is handed, `--blocks` and the blocks its change touches where its
 * mise.toml declares the flag, and nothing where it runs every block.
 */
let arguments: string => array<string>
