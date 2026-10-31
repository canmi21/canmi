/**
 * The pinned toolchain against each publisher's stable channel, `tools check|outdated|up`, and the
 * files an outside build reads written from the pins. See docs/toolchain.md.
 */
type response
@val external fetch: (string, {"headers": Dict.t<string>}) => promise<response> = "fetch"
@get external ok: response => bool = "ok"
@send external json: response => promise<JSON.t> = "json"
@send external body: response => promise<string> = "text"

let installLine = /^Would install (\S+)@(\S+)\s*$/gm
let ownerLine = /^Would bump (\S+)@\S+ in (.+?)\s*$/gm
let rustVersion = /^\[pkg\.rust\]\nversion = "(\d+\.\d+\.\d+)/m
let rustcVersion = /rustc (\d+\.\d+\.\d+)/
let digitsOnly = /^\d+$/
let leadingV = /^v/

/** Where a tool's stable channel is published; one absent from here has none this can read. */
let channels = Dict.fromArray([
  ("pnpm", ("npm", "pnpm")),
  ("oxlint", ("npm", "oxlint")),
  ("cargo-deny", ("github", "EmbarkStudios/cargo-deny")),
  ("jj", ("github", "jj-vcs/jj")),
  ("actionlint", ("github", "rhysd/actionlint")),
  ("shellcheck", ("github", "koalaman/shellcheck")),
  ("rclone", ("github", "rclone/rclone")),
  ("watchexec", ("github", "watchexec/watchexec")),
  ("node", ("node", "")),
  ("rust", ("rust", "")),
])

let field = (json: JSON.t, key) =>
  switch json {
  | Object(table) => table->Dict.get(key)
  | _ => None
  }
let textField = (json, key) =>
  switch field(json, key) {
  | Some(String(text)) => Some(text)
  | _ => None
  }

/** The part of a version a pin holds, the major or below 1.0 the minor, none for a channel. */
let series = (version: string): option<string> => {
  let parts = version->String.split(".")
  switch (parts[0], parts[1]) {
  | (Some(first), _) if !(digitsOnly->RegExp.test(first)) => None
  | (Some(first), _) if first != "0" => Some(first)
  | (Some(_), Some(second)) if digitsOnly->RegExp.test(second) => Some(`0.${second}`)
  | _ => None
  }
}

/** -1, 0 or 1, numeric where a part is a number, so 10 sorts above 9. */
let compareVersions = (a: string, b: string) => {
  let x = a->String.split(".")
  let y = b->String.split(".")
  let rec at = index =>
    switch (x[index], y[index]) {
    | (None, None) => 0
    | (None, Some(_)) => -1
    | (Some(_), None) => 1
    | (Some(p), Some(q)) =>
      let order = switch (digitsOnly->RegExp.test(p), digitsOnly->RegExp.test(q)) {
      | (true, true) =>
        compare(p->Int.fromString->Option.getOr(0), q->Int.fromString->Option.getOr(0))
      | (true, false) => -1
      | (false, true) => 1
      | (false, false) => compare(p, q)
      }
      order == 0 ? at(index + 1) : order
    }
  at(0)
}

let get = async url => {
  let response = await fetch(url, {"headers": Dict.fromArray([("User-Agent", "workspace-tools")])})
  response->ok ? Some(await response->json) : None
}

/**
 * What an outside build would resolve as `tool`'s current release, of `line` where one is named.
 */
let ask = async (tool, line: option<string>): option<string> =>
  try {
    switch channels->Dict.get(tool) {
    | Some(("npm", where)) =>
      switch await get(`https://registry.npmjs.org/${where}`) {
      | Some(document) =>
        let tags = field(document, "dist-tags")->Option.getOr(JSON.Null)
        let latest = textField(tags, "latest")
        switch line {
        | None => latest
        // The publisher's per-line tag where it keeps one; else `latest` answers for its own line
        // alone.
        | Some(line) =>
          switch textField(tags, `latest-${line}`) {
          | Some(tagged) => Some(tagged)
          | None =>
            latest->Option.flatMap(latest => series(latest) == Some(line) ? Some(latest) : None)
          }
        }
      | None => None
      }
    | Some(("github", where)) =>
      switch line {
      | None =>
        switch await Github.json(`https://api.github.com/repos/${where}/releases/latest`) {
        | Ok(release) if field(release, "prerelease") != Some(Boolean(true)) =>
          textField(release, "tag_name")->Option.map(tag => tag->String.replaceRegExp(leadingV, ""))
        | _ => None
        }
      // No endpoint answers a line's latest, so the list is walked, newest first, past drafts and
      // prereleases.
      | Some(line) =>
        switch await Github.releases(where) {
        | Ok(releases) =>
          releases->Array.reduce(None, (found, release) =>
            switch found {
            | Some(_) => found
            | None
              if field(release, "prerelease") != Some(Boolean(true)) &&
                field(release, "draft") != Some(Boolean(true)) =>
              textField(release, "tag_name")
              ->Option.map(tag => tag->String.replaceRegExp(leadingV, ""))
              ->Option.flatMap(tag => series(tag) == Some(line) ? Some(tag) : None)
            | None => None
            }
          )
        | _ => None
        }
      }
    | Some(("node", _)) =>
      switch await get("https://nodejs.org/dist/index.json") {
      | Some(Array(releases)) =>
        releases
        ->Array.filterMap(release =>
          textField(release, "version")->Option.map(v => v->String.replaceRegExp(leadingV, ""))
        )
        ->Array.find(version =>
          !(version->String.includes("-")) &&
          line->Option.mapOr(true, line => series(version) == Some(line))
        )
      | _ => None
      }
    | Some(("rust", _)) =>
      // The whole manifest, the version wanted inside [pkg.rust] and the first one cargo's.
      let response = await fetch(
        "https://static.rust-lang.org/dist/channel-rust-stable.toml",
        {"headers": Dict.fromArray([("User-Agent", "workspace-tools")])},
      )
      let text = await response->body
      rustVersion
      ->RegExp.exec(text)
      ->Option.flatMap(result => result->RegExp.Result.matches->Array.get(0))
      ->Option.flatMap(x => x)
    | _ => None
    }
  } catch {
  // A channel that cannot be read, wholly or halfway, is None, and every caller says so.
  | _ => None
  }

/** One answer per (tool, line) for the life of the process. */
let asked: Dict.t<promise<option<string>>> = Dict.make()
let stable = (tool, ~line=?) => {
  let key = `${tool} ${line->Option.getOr("")}`
  switch asked->Dict.get(key) {
  | Some(answer) => answer
  | None =>
    let answer = ask(tool, line)
    asked->Dict.set(key, answer)
    answer
  }
}

/** A directory's own tools as (tool, version), and what its `[tools]` asks for, read from mise. */
let current = where =>
  switch JSON.parseOrThrow(Node.output(~cwd=where, "mise", ["ls", "--current", "--json"])) {
  | Object(tools) => tools
  | _ => Dict.make()
  | exception _ => Dict.make()
  }

let own = (where, part) => {
  let mine = Node.resolve([Node.join([where, "mise.toml"])])
  current(where)
  ->Dict.toArray
  ->Array.flatMap(((tool, entries)) =>
    switch entries {
    | Array(entries) =>
      entries->Array.filterMap(entry =>
        switch field(entry, "source")->Option.flatMap(source => textField(source, "path")) {
        | Some(path) if path == mine => Some((tool, textField(entry, part)->Option.getOr("")))
        | _ => None
        }
      )
    | _ => []
    }
  )
  ->Array.toSorted(((a, _), (b, _)) => a < b ? -1. : 1.)
}

let installed = where => own(where, "version")
let pinned = where => own(where, "requested_version")->Dict.fromArray

/** Whether a pin would accept a version, which mise matches as its prefix. */
let allows = (pin, version) =>
  pin != "" && (version == pin || version->String.startsWith(`${pin}.`))

/** What `tool` resolves to in this directory, inherited or not. */
let active = (where, tool) =>
  switch current(where)->Dict.get(tool) {
  | Some(Array(entries)) => entries[0]->Option.flatMap(entry => textField(entry, "version"))
  | _ => None
  }

/** What rustup's stable toolchain is, asked by name, so no rust-toolchain.toml answers instead. */
let rustChannel = where =>
  rustcVersion
  ->RegExp.exec(Node.output(~cwd=where, "rustup", ["run", "stable", "rustc", "--version"]))
  ->Option.flatMap(result => result->RegExp.Result.matches->Array.get(0))
  ->Option.flatMap(x => x)

let channelLine = /channel\s*=\s*"([^"]+)"/

/**
 * (file, written, resolved) for the files an outside build reads, where they disagree with mise.
 */
let derived = (where): array<(string, string, string)> => {
  let found = []
  let nodeVersion = Node.join([where, ".node-version"])
  if Node.existsSync(nodeVersion) {
    let written = Node.readFileSync(nodeVersion)->String.trim
    switch active(where, "node") {
    | Some(running) if running != written => found->Array.push((nodeVersion, written, running))
    | _ => ()
    }
  }
  let toolchain = Node.join([where, "rust-toolchain.toml"])
  if Node.existsSync(toolchain) {
    switch (active(where, "rust"), channelLine->RegExp.exec(Node.readFileSync(toolchain))) {
    | (Some(running), Some(result)) =>
      switch result->RegExp.Result.matches {
      | [Some(written)] if written != running => found->Array.push((toolchain, written, running))
      | _ => ()
      }
    | _ => ()
    }
  }
  let manifest = Node.join([where, "package.json"])
  if Node.existsSync(manifest) {
    switch JSON.parseOrThrow(Node.readFileSync(manifest))->textField("packageManager") {
    | Some(declared) if declared->String.startsWith("pnpm@") =>
      let written = declared->String.slice(~start=5)
      switch active(where, "pnpm") {
      | Some(running) if running != written => found->Array.push((manifest, written, running))
      | _ => ()
      }
    | _ => ()
    }
  }
  found
}

let packageManager = /pnpm@[^"]+/

let writeDerived = (path, resolved) =>
  switch Node.basename(path) {
  | ".node-version" => Node.writeFileSync(path, `${resolved}\n`)
  | "rust-toolchain.toml" =>
    Node.writeFileSync(
      path,
      Node.readFileSync(path)->String.replaceRegExp(channelLine, `channel = "${resolved}"`),
    )
  | _ =>
    let text = Node.readFileSync(path)
    let start = text->String.indexOf("\"packageManager\"")
    let end = text->String.indexOfFrom("\n", start)
    let line = text->String.slice(~start, ~end)
    Node.writeFileSync(
      path,
      text->String.slice(~start=0, ~end=start) ++
      line->String.replaceRegExp(packageManager, `pnpm@${resolved}`) ++
      text->String.slice(~start=end),
    )
  }

/** The directories declaring tools of their own, as `Registry.selected` chooses them. */
let configured = (name, everything) =>
  Registry.selected(name, ~everything)->Array.filter(where =>
    Node.existsSync(Node.join([where, "mise.toml"]))
  )

/** Tools a project declares that the workspace already does, which mise lets it take over. */
let redundant = (where, provided: Dict.t<string>) =>
  installed(where)->Array.filterMap(((tool, version)) =>
    switch provided->Dict.get(tool) {
    | Some(theirs) if theirs == version =>
      Some(`declares ${tool} = ${version}, which the workspace already declares; drop it`)
    | Some(theirs) => Some(`pins ${tool} to ${version} over the workspace's ${theirs}`)
    | None => None
    }
  )

/** The files an outside build reads rewritten to what mise resolves; a redundant pin fails. */
let check = (~name=?, ~everything=false) => {
  let rewritten = ref(0)
  let shadowed = ref(0)
  let provided = installed(Registry.root)->Dict.fromArray
  configured(name, everything)
  ->Array.filter(where =>
    where == Registry.root || Waiting.skipped(Registry.label(where))->Option.isNone
  )
  ->Array.forEach(where => {
    derived(where)->Array.forEach(((path, written, resolved)) => {
      writeDerived(path, resolved)
      Console.log(
        `${Registry.label(where)}: ${Node.basename(path)} rewritten from ${written} to ${resolved}`,
      )
      rewritten := rewritten.contents + 1
    })
    if where != Registry.root {
      redundant(where, provided)->Array.forEach(complaint => {
        Console.log(`${Registry.label(where)} ${complaint}`)
        shadowed := shadowed.contents + 1
      })
    }
  })
  if rewritten.contents > 0 {
    Console.log("    an outside build reads these; commit them with the next change")
  }
  if shadowed.contents > 0 {
    Console.log("    a project declares a tool only where the workspace does not carry one")
    Console.log("    edit the project's [tools]; nothing rewrites it for you")
  }
  if rewritten.contents == 0 && shadowed.contents == 0 {
    Console.log("the versions an outside build reads agree with mise")
  }
  shadowed.contents > 0 ? 1 : 0
}

type row = {
  where: string,
  tool: string,
  version: string,
  pin: string,
  line: option<string>,
  newest: option<string>,
}

let survey = async (name, everything): array<row> => {
  let rows = []
  let rec walk = async places =>
    switch places {
    | list{} => ()
    | list{where, ...rest} =>
      let pins = pinned(where)
      let rec each = async tools =>
        switch tools {
        | list{} => ()
        | list{(tool, version), ...more} =>
          let line = switch series(version) {
          | Some(line) => await stable(tool, ~line)
          | None => None
          }
          let newest = await stable(tool)
          rows->Array.push({
            where,
            tool,
            version,
            pin: pins->Dict.get(tool)->Option.getOr(""),
            line,
            newest,
          })
          await each(more)
        }
      await each(List.fromArray(installed(where)))
      await walk(rest)
    }
  await walk(List.fromArray(configured(name, everything)))
  rows
}

/** One line per tool that is not where it should be; ahead is asked before across a pin. */
let report = (rows: array<row>) => {
  let lines = []
  let behind = ref(0)
  let ahead = ref(0)
  let unknown = ref(0)
  rows->Array.forEach(row => {
    let place = `${Registry.label(row.where)->String.padEnd(14, " ")} ${row.tool->String.padEnd(
        10,
        " ",
      )} ${row.version->String.padEnd(12, " ")}`
    switch row.newest {
    | None =>
      lines->Array.push(`${place} no stable channel to compare`)
      unknown := unknown.contents + 1
    | Some(newest) =>
      switch (series(row.version), row.line) {
      // A channel, which is current when the toolchain it resolves to is.
      | (None, _) =>
        switch row.tool == "rust" ? rustChannel(row.where) : None {
        | Some(holds) if holds != newest =>
          lines->Array.push(`${place} holds ${holds}, the channel is ${newest}`)
          behind := behind.contents + 1
        | _ => ()
        }
      | (Some(_), Some(line)) if compareVersions(row.version, line) > 0 =>
        lines->Array.push(`${place} is AHEAD of stable ${line}`)
        ahead := ahead.contents + 1
      | (Some(_), Some(line)) if row.version != line =>
        let within = allows(row.pin, line) ? "inside the pin" : `held back by the pin "${row.pin}"`
        lines->Array.push(`${place} -> ${line} ${within}`)
        behind := behind.contents + 1
      | (version, _) if version != series(newest) =>
        lines->Array.push(`${place} -> ${newest} across a pin`)
        behind := behind.contents + 1
      | _ if row.version != newest =>
        lines->Array.push(`${place} -> ${newest}`)
        behind := behind.contents + 1
      | _ => ()
      }
    }
  })
  (lines, behind.contents, ahead.contents, unknown.contents)
}

let outdated = async (~name=?, ~everything=false) => {
  let (lines, behind, ahead, unknown) = report(await survey(name, everything))
  lines->Array.forEach(line => Console.log(line))
  if behind == 0 && ahead == 0 {
    Console.log(
      unknown > 0
        ? "every tool this can ask about is on its publisher's stable release"
        : "every tool is on its publisher's stable release",
    )
  } else if ahead > 0 {
    Console.log(
      "\nA version ahead of stable is on a prerelease line. Pin it down to the stable one.",
    )
  }
  0
}

let pairs = (pattern: RegExp.t, text) => {
  let found = []
  pattern->RegExp.setLastIndex(0)
  let rec next = () =>
    switch pattern->RegExp.exec(text) {
    | Some(result) =>
      switch result->RegExp.Result.matches {
      | [Some(a), Some(b)] => found->Array.push((a, b))
      | _ => ()
      }
      next()
    | None => ()
    }
  next()
  found
}

let machineRows = (rows: array<row>) =>
  rows->Array.flatMap(row => {
    let from = row.tool == "rust" ? rustChannel(row.where)->Option.getOr(row.version) : row.version
    let targets =
      [row.line, row.newest]
      ->Array.filterMap(value => value)
      ->Array.reduce([], (seen, version) =>
        seen->Array.includes(version) ? seen : [...seen, version]
      )
    targets->Array.filterMap(version =>
      compareVersions(version, from) > 0
        ? Some(
            Reminder.item(
              ~repository=Registry.label(row.where),
              allows(row.pin, version) || row.pin == "stable" ? "tool" : "major",
              row.tool,
              from,
              version,
            ),
          )
        : None
    )
  })

let machine = async where => {
  let repository = Registry.label(where)
  let before = installed(where)->Dict.fromArray
  let names = before->Dict.keysToArray
  let upgraded =
    names == [] ? "" : Node.output(~cwd=where, "mise", ["upgrade", ...names, "--dry-run"])
  let items = pairs(installLine, upgraded)->Array.filterMap(((name, version)) =>
    before
    ->Dict.get(name)
    ->Option.flatMap(from =>
      from != version ? Some(Reminder.item(~repository, "tool", name, from, version)) : None
    )
  )
  let missing = Node.output(~cwd=where, "mise", ["ls", "--missing", "--json"])
  try {
    switch JSON.parseOrThrow(missing) {
    | Object(tools) =>
      tools
      ->Dict.toArray
      ->Array.forEach(((name, entries)) =>
        switch entries {
        | Array(entries) =>
          entries->Array.forEach(entry => {
            let source = field(entry, "source")->Option.flatMap(source => textField(source, "path"))
            if source == Some(Node.join([where, "mise.toml"])) {
              items->Array.push(
                Reminder.item(
                  ~repository,
                  "missing",
                  name,
                  "not installed",
                  textField(entry, "version")->Option.getOr(""),
                ),
              )
            }
          })
        | _ => ()
        }
      )
    | _ => ()
    }
  } catch {
  | _ => ()
  }
  let rows = await survey(Some(repository), false)
  Array.concat(items, machineRows(rows))->Array.reduce([], (seen, item) =>
    seen->Array.some(existing => Reminder.same(existing, item)) ? seen : [...seen, item]
  )
}

/**
 * What `mise upgrade --bump` would take in this directory, against its own line's stable release.
 */
let beyond = async where => {
  let said = Node.output(~cwd=where, "mise", ["upgrade", "--bump", "--dry-run"])
  let installs = pairs(installLine, said)->Dict.fromArray
  let found = []
  let rec each = async owners =>
    switch owners {
    | list{} => ()
    | list{(tool, owner), ...rest} =>
      switch installs->Dict.get(tool) {
      | Some(version) =>
        let owner =
          owner->String.startsWith("~")
            ? Node.join([
                Node.env->Dict.get("HOME")->Option.getOr(""),
                owner->String.slice(~start=1),
              ])
            : owner

        // A pin of the workspace's, seen from a repository below it, is the workspace's row.
        if where == Registry.root || owner->String.startsWith(where) {
          let shown =
            owner->String.startsWith(Registry.root) ? Node.relative(Registry.root, owner) : owner
          let current = switch series(version) {
          | Some(line) => await stable(tool, ~line)
          | None => None
          }
          found->Array.push((shown, tool, version, current))
        }
      | None => ()
      }
      await each(rest)
    }
  await each(List.fromArray(pairs(ownerLine, said)))
  found
}

let up = async (~name=?, ~everything=false, ~dry=false) => {
  let places = configured(name, everything)
  if places->Array.length == 0 {
    Console.log(
      `repos/${name->Option.getOr(
          "",
        )} declares no tools of its own; the workspace's are not touched`,
    )
    0
  } else {
    // rust is rustup's toolchain, which mise cannot move, so rustup advances it.
    if places->Array.some(where => installed(where)->Array.some(((tool, _)) => tool == "rust")) {
      if dry {
        Console.log("would run rustup update stable")
      } else if Node.run(~cwd=Registry.root, "rustup", ["update", "stable"]) != 0 {
        Console.log("rustup update failed; rust is left where it was")
      }
    }
    let moved = []
    let waiting = []
    let rec each = async remaining =>
      switch remaining {
      | list{} => ()
      | list{where, ...rest} =>
        let before = installed(where)->Dict.fromArray
        let ran = Node.spawnSync(
          "mise",
          Array.concat(["upgrade", "--local"], dry ? ["--dry-run"] : []),
          {cwd: where, encoding: "utf8", maxBuffer: 268435456},
        )
        let stdout = ran.stdout->Nullable.getOr("")
        // mise's advice to bump is dropped, as it reads every published version and no stable tag.
        [stdout, ran.stderr->Nullable.getOr("")]->Array.forEach(stream =>
          stream
          ->String.split("\n")
          ->Array.forEach(line =>
            if (
              line != "" &&
              !(line->String.includes("upgrade --bump")) &&
              !(dry && line->String.startsWith("Would "))
            ) {
              Console.log(line)
            }
          )
        )
        if ran.status != Nullable.make(0) {
          Registry.fail(`mise upgrade failed in ${Registry.label(where)}`)
        }
        (await beyond(where))->Array.forEach(row =>
          if !(waiting->Array.some(one => one == row)) {
            waiting->Array.push(row)
          }
        )
        let after = dry
          ? {
              let would = before->Dict.copy
              pairs(installLine, stdout)->Array.forEach(((tool, version)) =>
                if before->Dict.get(tool)->Option.isSome {
                  would->Dict.set(tool, version)
                }
              )
              would
            }
          : installed(where)->Dict.fromArray
        before
        ->Dict.toArray
        ->Array.forEach(((tool, was)) =>
          if after->Dict.get(tool) != Some(was) {
            moved->Array.push((
              Registry.label(where),
              tool,
              was,
              after->Dict.get(tool)->Option.getOr("?"),
            ))
          }
        )
        await each(rest)
      }
    await each(List.fromArray(places))
    // The files an outside build reads are written from the pins, wherever the toolchain moved.
    let rewritten = places->Array.flatMap(where =>
      derived(where)->Array.map(((path, _, current)) => {
        if !dry {
          writeDerived(path, current)
        }
        (Registry.label(where), Node.basename(path), current)
      })
    )
    Console.log("")
    rewritten->Array.forEach(((place, written, resolved)) =>
      Console.log(
        `${place->String.padEnd(14, " ")} ${written->String.padEnd(16, " ")} ${dry
            ? "would be rewritten to"
            : "rewritten to"} ${resolved}`,
      )
    )
    if moved->Array.length > 0 {
      moved->Array.forEach(((place, tool, was, now)) =>
        Console.log(
          `${place->String.padEnd(14, " ")} ${tool->String.padEnd(10, " ")} ${dry
              ? "would move"
              : "moved"} ${was} -> ${now}`,
        )
      )
      if !dry {
        Console.log(
          "\nRun each repository's verify before trusting this; a toolchain move is a change.",
        )
      }
    } else {
      Console.log("everything is current within its pins")
    }
    if waiting->Array.length > 0 {
      Console.log("\nBeyond the pins, and what channel each is actually on:\n")
      waiting->Array.forEach(((owner, tool, version, current)) => {
        let verdict = switch current {
        | None => "no stable channel to compare"
        | Some(current) if compareVersions(version, current) > 0 =>
          `ahead of stable ${current}; a prerelease line, do not take it`
        | Some(_) => "stable; edit [tools] to cross the pin"
        }
        Console.log(
          `${owner->String.padEnd(24, " ")} ${tool->String.padEnd(
              10,
              " ",
            )} ${version->String.padEnd(12, " ")} ${verdict}`,
        )
      })
    }
    let (lines, _, _, _) = report(await survey(name, everything))
    if lines->Array.length > 0 {
      Console.log("\n" ++ String.repeat("-", 72))
      Console.log("Against each publisher's stable channel:\n")
      lines->Array.forEach(line => Console.log(line))
      Console.log("\n  a pin is crossed by editing [tools]; nothing here does it for you")
    }
    0
  }
}

let usage = "usage: tools check | outdated | up  [name | --all] [--dry-run]"

let main = async () => {
  let args = Node.args()
  let dry = args->Array.some(arg => arg == "-n" || arg == "--dry-run")
  let everything = args->Array.some(arg => arg == "-a" || arg == "--all")
  args->Array.forEach(arg =>
    if arg->String.startsWith("-") && !(["-n", "--dry-run", "-a", "--all"]->Array.includes(arg)) {
      Registry.fail(`unknown option ${arg}`)
    }
  )
  let rest = args->Array.filter(arg => !(arg->String.startsWith("-")))
  if rest->Array.length > 2 {
    Registry.fail(
      `one name at most; ${rest->Array.slice(~start=2)->Array.join(" ")} would have been ignored`,
    )
  }
  let name = rest[1]
  switch rest[0] {
  | Some("check") => check(~name?, ~everything)
  | Some("outdated") => await outdated(~name?, ~everything)
  | Some("up") => await up(~name?, ~everything, ~dry)
  | _ => Registry.fail(usage)
  }
}

if Node.isMain {
  main()
  ->Promise.thenResolve(code => Node.exit(code))
  ->Promise.catch(error => {
    switch error {
    | Registry.Refused(why) => Console.error(`error: ${why}`)
    | JsExn(error) => Console.error(`error: ${error->JsExn.message->Option.getOr("")}`)
    | _ => Console.error("error: tools failed")
    }
    Node.exit(1)
  })
  ->ignore
}
