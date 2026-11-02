/** Each changed package raised at a landing on a main line, a lane and a paused one aside. */
let skipped = () =>
  Node.env
  ->Dict.get(Commits.skip)
  ->Option.getOr("")
  ->String.split(",")
  ->Array.map(String.trim)

let majorEscape = "major"

let judged = root =>
  Landing.isJj(root) &&
  Form.mainCheckout(root) &&
  Waiting.pauser(~repo=Registry.label(root))->Option.isNone

let authorOnly = line => line->String.includes("only the author")

/** A line of `Numbers.broken` with what ends it, a moved major naming its escape. */
let said = (~pushing=false, name, line) =>
  `${name} ${line}${authorOnly(line)
      ? `, or name it, ${Commits.skip}=${majorEscape} mise run ${pushing ? "push" : "check"}`
      : ", run mise run bump"}`

let kept = line => !authorOnly(line) || !(skipped()->Array.includes(majorEscape))

let stale = (~root, ~read, ~pushing=false, lock, packages) => {
  let own =
    lock->Option.mapOr([], lock =>
      Packages.lockStale(lock, Roll.crates(packages, ~version=package => package.version))
    )
  let sibling = if pushing {
    switch Roll.siblingVersions(~root, ~read, packages) {
    | Error(why) => [why]
    | Ok(crates) =>
      lock->Option.mapOr([], lock =>
        Packages.lockStale(lock, crates)->Array.map(line =>
          line ++ ", restore the committed lock to the pin's versions or move the pin"
        )
      )
    }
  } else {
    []
  }
  [...own, ...sibling]
}

/** What a repository's landing leaves undone, each line naming the package. */
let found = (~root) =>
  if !judged(root) {
    []
  } else {
    let judged = Roll.judged(~root)
    Array.flat([
      judged.problems,
      judged.rows->Array.flatMap(row =>
        Numbers.broken(row.asked)
        ->Array.filter(kept)
        ->Array.map(line => said(row.package.name, line))
      ),
      stale(
        ~root,
        ~read=path => Landing.disk(~root, path),
        Landing.disk(~root, "Cargo.lock"),
        judged.packages,
      ),
    ])
  }

/**
 * The part again over what a push sends, a raise in any later outgoing commit paying what an
 * earlier one owes, so a landing committed by path passes and one with no raise does not.
 */
let outgoing = (~root) =>
  if !judged(root) {
    []
  } else {
    let states = Roll.outgoing(~root)
    let owed = Roll.replay(states)
    let moved = states->Array.flatMap(((commit, state)) =>
      state.rows->Array.flatMap(row =>
        Numbers.broken(row.asked)
        ->Array.filter(line => authorOnly(line) && kept(line))
        ->Array.map(
          line =>
            `${commit->String.slice(~start=0, ~end=12)}: ${said(
                ~pushing=true,
                row.package.name,
                line,
              )}`,
        )
      )
    )
    let tip = states->Array.at(-1)
    Array.flat([
      moved,
      owed
      ->Dict.toArray
      ->Array.map(((name, debt)) =>
        `${debt.commit->String.slice(~start=0, ~end=12)}: ${name} owing ${Numbers.show(
            debt.wanted,
          )}, run mise run bump`
      ),
      switch tip {
      | Some((commit, tip)) =>
        let read = path => Landing.at(~root, ~base=commit, path)
        stale(~root, ~read, ~pushing=true, read("Cargo.lock"), tip.packages)
      | _ => []
      },
    ])
  }
