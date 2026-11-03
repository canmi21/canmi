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

/** Each block by its name and the blocks it uses, its same-scoped dependencies. */
let usesOf: string => array<(string, array<string>)>

/** The blocks named and every block using one of them, at any depth, in the order `uses` gives. */
let withDependents: (array<string>, ~uses: array<(string, array<string>)>) => array<string>

/**
 * What a repository's verify is handed, `--blocks`, the blocks its change touches and their
 * dependents, where its mise.toml declares the flag, and nothing where it runs every block.
 */
let arguments: string => array<string>

/**
 * A repository's table of what its verify parts cover, from its workspace.toml's
 * `[[check.touched]]` rows, each `paths`, globs where `**` crosses directories and `*` does not,
 * and `parts`, its `verify:<part>` names; none where it declares no row.
 */
let tableOf: string => option<array<(array<string>, array<string>)>>

/**
 * The verify parts a change touches, each once in the order the table first names it, none for a
 * change whose rows name no part; `None` where a changed path matches no row, so the whole verify.
 */
let parts: (
  ~paths: array<string>,
  ~table: array<(array<string>, array<string>)>,
) => option<array<string>>
