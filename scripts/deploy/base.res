/**
 * The base a push's Deploy run plans against, printed, and nothing to build everything: `node
 * base.res.mjs` in CI, from the repository's checkout. It is the head commit of the last Deploy run
 * on main that a push started and that succeeded, so every change since what was last built is
 * built now; `github.event.before` is the base only where the API cannot answer, since GitHub
 * cancels a pending run when another push queues. Reads `GITHUB_REPOSITORY`, `GH_TOKEN` and
 * `BEFORE`.
 */
let workflow = "deploy.yml"
let branch = "main"
let timeout = 30000

/** The API gave no answer that can be read. */
exception Unanswered(string)

/** The newest run of the Deploy workflow on main a push started and that succeeded. */
let runsPath = repository =>
  `repos/${repository}/actions/workflows/${workflow}/runs?branch=${branch}&event=push&status=success&per_page=1`

type ran = {status: Nullable.t<int>, stdout: string, stderr: string, error: option<JsExn.t>}

/** How `gh` is run, replaced whole by the tests. */
type run = (string, array<string>) => ran

type timed = {encoding: string, timeout: int}
@module("node:child_process")
external spawnTimed: (string, array<string>, timed) => Node.spawned = "spawnSync"

let run: run = (command, args) => {
  let ran = spawnTimed(command, args, {encoding: "utf8", timeout})
  {
    status: ran.status,
    stdout: ran.stdout->Nullable.getOr(""),
    stderr: ran.stderr->Nullable.getOr(""),
    error: ran.error->Nullable.toOption,
  }
}

let unreadable = why => throw(Unanswered(`an answer it cannot read: ${why}`))

/**
 * That run's head commit; None when there is none. Throws Unanswered when the API does not answer.
 */
let lastBuilt = (repository: string, ~ask: run=run): option<string> => {
  if repository == "" {
    throw(Unanswered("GITHUB_REPOSITORY is not set"))
  }
  let ran = ask("gh", ["api", runsPath(repository)])
  switch ran.error {
  | Some(error) => throw(Unanswered(error->JsExn.message->Option.getOr("")))
  | None => ()
  }
  if ran.status != Nullable.make(0) {
    let said = ran.stderr->String.trim->String.split("\n")->Array.getUnsafe(0)
    throw(
      Unanswered(
        said != ""
          ? said
          : `gh exited ${ran.status
              ->Nullable.toOption
              ->Option.mapOr("null", status => Int.toString(status))}`,
      ),
    )
  }
  let answer = try JSON.parseOrThrow(ran.stdout) catch {
  | JsExn(error) => unreadable(error->JsExn.message->Option.getOr(""))
  }
  switch answer {
  | Object(answer) =>
    switch answer->Dict.get("workflow_runs") {
    | None => unreadable("no workflow_runs")
    // No run at all: null, an empty list or an empty table.
    | Some(Null) | Some(Array([])) => None
    | Some(Object(runs)) if runs->Dict.keysToArray->Array.length == 0 => None
    | Some(Array(runs)) =>
      switch runs->Array.getUnsafe(0) {
      | Object(first) =>
        switch first->Dict.get("head_sha") {
        | Some(String(sha)) => Some(sha)
        | _ => unreadable("no head_sha")
        }
      | _ => unreadable("no head_sha")
      }
    | Some(_) => unreadable("workflow_runs is no list")
    }
  | _ => unreadable("no workflow_runs")
  }
}

/** Whether the checkout has `commit` and HEAD descends from it. */
let holds = (commit: string, ~checkout=?) =>
  [
    ["cat-file", "-e", `${commit}^{commit}`],
    ["merge-base", "--is-ancestor", commit, "HEAD"],
  ]->Array.every(args => Node.spawnSync("git", args, {cwd: ?checkout}).status == Nullable.make(0))

let zeros = /^0+|0+$/g

/** No commit at all: GitHub's `before` for a branch's first push is forty zeros. */
let isZero = commit => commit->String.replaceRegExp(zeros, "") == ""

let fallback = (before, why) =>
  isZero(before)
    ? ("", `${why}, and the push names no commit before it: building everything`)
    : (before, `${why}: planning against github.event.before, ${before}`)

/**
 * (base, why): the base to plan against, empty for everything. `asked()` answers the last commit
 * built or throws Unanswered; `descends(commit)` says whether HEAD descends from it.
 */
let base = (
  asked: unit => option<string>,
  before: string,
  head: string,
  descends: string => bool,
) =>
  switch asked() {
  | exception Unanswered(why) => fallback(before, `the API did not answer (${why})`)
  | None => ("", "no Deploy run a push started on main has succeeded: building everything")
  // A run re-run at the commit already built: what its own push changed, as a re-run always built.
  | Some(built) if built == head => fallback(before, `the last run built ${built}, which is HEAD`)
  | Some(built) if !descends(built) => (
      "",
      `the last run built ${built}, which HEAD does not descend from: building everything`,
    )
  | Some(built) => (
      built,
      `planning against ${built}, the last Deploy run a push started on main to succeed`,
    )
  }

if Node.isMain {
  let head = Node.output("git", ["rev-parse", "HEAD"])->String.trim
  let repository = Node.env->Dict.get("GITHUB_REPOSITORY")->Option.getOr("")
  let (chosen, why) = base(
    () => lastBuilt(repository),
    Node.env->Dict.get("BEFORE")->Option.getOr(""),
    head,
    commit => holds(commit),
  )
  Console.error(`deploy-base: ${why}`)
  Console.log(chosen)
}
