/***
 * One landing of a repository's working copy through the workspace's verbs, stopping at its first
 * failure, docs/commits.md. The model's interface, `docs/code.md`.
 */

/**
 * What a landing is asked, from `land <name> -m <subject> ...`; `thread`, from `--thread <name>`,
 * the thread the landing is recorded in by `thread landed`, none where it is not given.
 */
type asked = {
  repository: string,
  subject: string,
  trailers: array<string>,
  paths: array<string>,
  thread: option<string>,
  dry: bool,
}

/** The arguments read, or why they are refused, the usage among it. */
let parse: array<string> => result<asked, string>

/**
 * One step of a landing: the repository's format, its bump, its check (form, format, the rule
 * parts, then the touched parts), the commit, main moved to it, the push's dry run then the push,
 * and the landing recorded in its thread where one is given.
 */
type step =
  | Format
  | Bump
  | Check
  | Commit
  | Bookmark
  | PushDry
  | Push
  | Record

/** The steps in their order. */
let steps: array<step>

/** A step as the command it runs for what was asked, the commit's message whole among it. */
let command: (asked, step) => (string, array<string>)

/**
 * Each step run in order from the workspace, stopping at the first that fails with its causes last;
 * a dry run says each command and runs none. The exit status.
 */
let run: asked => promise<int>
