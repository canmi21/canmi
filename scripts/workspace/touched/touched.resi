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
