/** At the end of a turn: refuse to hand back commits main does not cover; never move it here. */
let bookmark = "main"

/** Described, non-empty commits on the way to the working copy that the bookmark does not cover. */
let revset = `::@ ~ ::${bookmark} ~ empty()`
let template = `if(description, change_id.short() ++ "\\t" ++ description.first_line() ++ "\\n")`

let ahead = (~cwd) =>
  Payload.jj(~cwd, ["log", "--no-graph", "--ignore-working-copy", "-r", revset, "-T", template])
  ->String.split("\n")
  ->Array.filterMap(line =>
    switch line->String.split("\t") {
    | [change, subject] => Some((change, subject))
    | _ => None
    }
  )

/** The decision the harness reads, or none; a second stop goes through, as a hold has no exit. */
let response = (payload: Payload.t): option<JSON.t> =>
  if payload->Payload.flag("stop_hook_active") {
    None
  } else {
    switch ahead(~cwd=Payload.cwd(payload)) {
    | [] => None
    | found =>
      let listed =
        found->Array.map(((change, subject)) => `  ${change}  ${subject}`)->Array.join("\n")
      let reason =
        `\`${bookmark}\` does not cover ${Int.toString(
            found->Array.length,
          )} commit(s) on the way ` ++
        `to the working copy:\n${listed}\n\n` ++
        `docs/commits.md: a finished task is committed *and* the bookmark is moved before the ` ++
        `result is handed back. Committed work is finished work -- partial work is meant to stay ` ++
        `uncommitted -- so anything listed above belongs under the bookmark.\n\n` ++
        `Run \`jj bookmark move ${bookmark} --to @-\`, or \`--to @\` followed by \`jj new\` when ` ++
        `the working copy is itself the described commit, so the working copy ends above the ` ++
        `bookmark. If the move is refused as sideways, ${bookmark} moved meanwhile: \`jj rebase ` ++
        `-d ${bookmark}\`, run the repository's check again -- \`mise run check\` names it -- ` ++
        `then move. When to push is docs/commits.md, "When a change is done, and when it is ` ++ `pushed". Then finish the turn.`
      Some(
        JSON.Object(
          Dict.fromArray([("decision", JSON.String("block")), ("reason", JSON.String(reason))]),
        ),
      )
    }
  }
