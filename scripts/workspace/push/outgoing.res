/** What `push` sends, and the gates it passes first. See docs/agents/pushing.md. */
let ahead = repo => {
  let result = Node.spawnSync(
    "jj",
    [
      "log",
      "--no-graph",
      "-r",
      `remote_bookmarks(exact:"main", exact:"origin")..main ~ root()`,
      "-T",
      `commit_id.short() ++ "\\n"`,
    ],
    {cwd: repo, encoding: "utf8", maxBuffer: 268435456},
  )
  if result.status != Nullable.make(0) {
    Console.log(`${Registry.label(repo)}: cannot tell what to push`)
    Console.error(result.stderr->Nullable.getOr(""))
    None
  } else {
    Some(Onset.lines(result.stdout->Nullable.getOr("")))
  }
}

/**
 * Each public repository with commits to push scanned by `Scan.judged`, a hit sent refusing every
 * push. See docs/agents/pushing.md, "A push carries nothing private".
 */
let scanned = (pending: array<(string, option<array<string>>)>, ~dry) => {
  let nothing = dry ? "a push would push nothing" : "push pushes nothing"
  let outgoing = pending->Array.filterMap(((repo, commits)) =>
    switch commits {
    | None | Some([]) => None
    | Some(_) =>
      switch Project.visibilityAt(repo) {
      | Ok(visibility) => Some((repo, visibility == Project.public))
      | Error(why) => Registry.fail(`${why}, so ${nothing}`)
      }
    }
  )
  if outgoing->Array.some(((_, public)) => public) {
    let identifiers = switch Scan.identifiers() {
    | Some(identifiers) => identifiers
    | None =>
      Registry.fail(
        `no list of private identifiers that reads whole at ${Toolchain.privateIdentifiers}, ` ++
        `each exception a pattern, which a ` ++
        `public repository's push is scanned against, so ${nothing}`,
      )
    }
    let skip = Node.env->Dict.get(Commits.skip)
    let refused = outgoing->Array.flatMap(((repo, public)) => {
      let place = Registry.label(repo)
      switch Scan.judged(~public, ~skip, () => Scan.repository(repo, identifiers)) {
      | Error(why) => Registry.fail(`${place} cannot be scanned, ${why}, so ${nothing}`)
      | Ok({refused, passed, warned}) =>
        warned->Array.forEach(hit =>
          Console.log(`warning: ${Scan.shown(place, hit)}, already tracked`)
        )
        passed->Array.forEach(hit =>
          Console.log(`passed by ${Commits.skip}=${Scan.gate}: ${Scan.shown(place, hit)}`)
        )
        refused->Array.map(hit => Scan.shown(place, hit))
      }
    })
    if refused != [] {
      refused->Array.forEach(line => Console.error(line))
      Registry.fail(
        `a private identifier stands in what would be sent, so ${nothing}; one that is no leak ` ++
        `passes by \`${Commits.skip}=${Scan.gate} mise run push ...\``,
      )
    }
  }
}

/**
 * Push main wherever origin is behind it, an origin with no main yet behind by all of it, once the
 * form layer holds nothing in any of them.
 */
let push = (name, ~dry, ~everything) => {
  let selected = Registry.selected(name, ~everything)->Array.filter(Registry.isRepository)
  let pending = switch Push_state.planned(selected, repo =>
    Push_state.ready(args => Scan.jj(repo, args), ~place=Registry.label(repo))
    ->Result.flatMap(_ =>
      switch ahead(repo) {
      | Some(commits) => Ok(commits)
      | None => Error("cannot tell what to push")
      }
    )
    ->Result.mapError(why => `${Registry.label(repo)}: ${why}`)
  ) {
  | Ok(pending) => pending
  | Error(why) => Registry.fail(Push_state.stopped(why, ~dry))
  }
  let held = pending->Array.filter(((repo, commits)) =>
    switch commits {
    | Some([]) | None => false
    | Some(_) => Check.gate(repo, ~bookmarks=["main"]) != 0
    }
  )
  if held != [] {
    Registry.fail(
      `the form layer holds a warning in ${held
        ->Array.map(((repo, _)) => Registry.label(repo))
        ->Array.join(", ")}, so ${dry ? "a push would push" : "push pushes"} nothing`,
    )
  }
  let unrolled = pending->Array.flatMap(((repo, commits)) =>
    switch commits {
    | Some([]) | None => []
    | Some(_) =>
      Versions.outgoing(~root=repo)->Array.map(line => `${Registry.label(repo)}: ${line}`)
    }
  )
  if unrolled != [] {
    unrolled->Array.forEach(line => Console.error(line))
    Registry.fail(
      `an outgoing commit owes a version, so ${dry ? "a push would push" : "push pushes"} nothing`,
    )
  }
  scanned(pending, ~dry)
  pending->Array.forEach(((repo, commits)) => {
    let place = Registry.label(repo)
    switch commits {
    | None => ()
    | Some([]) => Console.log(`${place}: nothing to push`)
    | Some(commits) =>
      Console.log(
        `${place}: ${dry ? "would push" : "pushing"} ${Int.toString(
            commits->Array.length,
          )} commit(s)`,
      )
      let flags = dry ? ["--dry-run"] : []
      if Node.run(~cwd=repo, "jj", ["git", "push", "--bookmark", "main", ...flags]) != 0 {
        Registry.fail(`jj git push failed in ${place}`)
      }
    }
  })
  0
}
