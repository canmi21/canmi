/** Refuses a Codex run while Codex has no quota, the quota rule of docs/agents/delegation.md. */
let reader = "node"
let script = ".claude/plugins/marketplaces/claude-dashboard/dist/check-usage.js"

/** Subcommands of codex that make a model call. */
let calling = ["exec", "e", "review"]
/** Options of codex that take a value, which is not the subcommand. */
let valued = [
  "-m",
  "--model",
  "-c",
  "--config",
  "-C",
  "--cd",
  "-p",
  "--profile",
  "-i",
  "--image",
  "-s",
  "--sandbox",
  "-a",
  "--ask-for-approval",
  "--add-dir",
  "--color",
  "--enable",
  "--disable",
  "--local-provider",
]
/** Words that open a compound command's body and run what follows. */
let openers = ["if", "then", "else", "elif", "do", "while", "until", "!", "{", "}", "time"]

let heredocAs = /<<-?\s*(['"]?)([A-Za-z_][A-Za-z0-9_]*)\1/

/**
 * The command with each here-document's body dropped and each group, background mark and brace cut
 * to a separator.
 */
let flattened = command => {
  let kept = []
  let ending = ref(None)
  command
  ->String.split("\n")
  ->Array.forEach(line =>
    switch ending.contents {
    | Some(delimiter) => line->String.trim == delimiter ? ending := None : ()
    | None =>
      kept->Array.push(line)
      ending :=
        heredocAs
        ->RegExp.exec(line)
        ->Option.flatMap(found => found->Array.get(2))
        ->Option.flatMap(group => group)
    }
  )
  let chars = kept->Array.join("\n")->Node.codePoints
  let out = ref("")
  let quote = ref("")
  let substitutions = ref([])
  chars->Array.forEachWithIndex((char, at) => {
    let before = at > 0 ? chars->Array.getUnsafe(at - 1) : ""
    let after = chars[at + 1]->Option.getOr("")
    if quote.contents == "'" {
      out := out.contents ++ char
      char == "'" ? quote := "" : ()
    } else if before == "\\" {
      out := out.contents ++ char
    } else if quote.contents == "\"" {
      out := out.contents ++ char
      char == "\"" ? quote := "" : ()
    } else if char == "'" || char == "\"" {
      quote := char
      out := out.contents ++ char
    } else if char == "(" {
      substitutions := Array.concat([before == "$"], substitutions.contents)
      out := out.contents ++ (before == "$" ? char : ";")
    } else if char == ")" {
      let sub = substitutions.contents[0]->Option.getOr(false)
      substitutions := substitutions.contents->Array.slice(~start=1)
      out := out.contents ++ (sub ? char : ";")
    } else if (
      char == "&" && after != "&" && before != "&" && before != ">" && before != "<" && after != ">"
    ) {
      out := out.contents ++ ";"
    } else {
      out := out.contents ++ char
    }
  })
  out.contents
}

let rec dropOpeners = (words: array<string>) =>
  switch words[0] {
  | Some(first) if openers->Array.includes(first) => dropOpeners(words->Array.slice(~start=1))
  | _ => words
  }

/** Whether the words after `codex` run a subcommand that makes a model call. */
let codexCalls = (rest: array<string>) => {
  let at = ref(0)
  let outcome = ref(None)
  while outcome.contents == None && at.contents < rest->Array.length {
    let word = rest->Array.getUnsafe(at.contents)
    if ["-h", "--help", "-V", "--version", "help"]->Array.includes(word) {
      outcome := Some(false)
    } else if valued->Array.includes(word) {
      at := at.contents + 2
    } else if word->String.startsWith("-") {
      at := at.contents + 1
    } else {
      outcome := Some(calling->Array.includes(word))
    }
  }
  outcome.contents->Option.getOr(false)
}

/**
 * Whether a command line runs a Codex model call in any segment, through a shell's -c and mise
 * exec as well.
 */
let rec runs = (command: string) =>
  Jj_command.segments(flattened(command))->Array.some(segment => callsIn(dropOpeners(segment)))
and callsIn = (segment: array<string>) =>
  switch Jj_command.commandAt(segment) {
  | None => false
  | Some(at) =>
    let argv = segment->Array.slice(~start=at)
    switch argv[0]->Option.map(Node.basename) {
    | Some("codex") => codexCalls(argv->Array.slice(~start=1))
    | Some("mise") =>
      switch argv->Array.findIndex(word => word == "--") {
      | -1 => false
      | dash => callsIn(dropOpeners(argv->Array.slice(~start=dash + 1)))
      }
    | Some(program) if Delegation.shells->Array.includes(program) =>
      let rest = argv->Array.slice(~start=1)
      switch rest->Array.findIndex(word => /^-[A-Za-z]*c[A-Za-z]*$/->RegExp.test(word)) {
      | -1 => false
      | flag => rest[flag + 1]->Option.mapOr(false, runs)
      }
    | _ => false
    }
  }

type reading = Limited(string) | Free | Unknown

let percent = (entry: Dict.t<JSON.t>, key) =>
  switch entry->Dict.get(key) {
  | Some(JSON.Number(value)) => Some(value)
  | _ => None
  }

/** What check-usage's JSON says of Codex, limited while either window reads 100. */
let read = (json: string): reading =>
  switch Payload.parse(json)->Option.flatMap(all => all->Payload.object("codex")) {
  | None => Unknown
  | Some(codex) =>
    switch (codex->percent("fiveHourPercent"), codex->percent("sevenDayPercent")) {
    | (None, None) => Unknown
    | (five, seven) =>
      let full =
        [(five, "fiveHourReset"), (seven, "sevenDayReset")]->Array.filterMap(((used, key)) =>
          used->Option.flatMap(used =>
            used >= 100. ? Some(codex->Payload.text(key)->Option.getOr("an unknown time")) : None
          )
        )
      // Both windows must have room again, so the later reset, compared as dates.
      let time = text => {
        let parsed = Date.fromString(text)->Date.getTime
        Float.isNaN(parsed) ? Float.Constants.negativeInfinity : parsed
      }
      switch full->Array.toSorted((a, b) => Float.compare(time(b), time(a)))->Array.get(0) {
      | Some(resets) => Limited(resets)
      | None => Free
      }
    }
  }

let home = () => Node.env->Dict.get("HOME")->Option.getOr("")

let modelAs = /^model\s*=\s*["']([^"']+)["']\s*(?:#.*)?$/m

/**
 * Whether check-usage would know Codex's model without running `codex exec "1+1="` itself, which it
 * does once the usage call succeeds, with no model in ~/.codex/config.toml and no cache for it,
 * costing a model call and up to ten seconds.
 */
let modelKnown = () => {
  let config = Node.join([home(), ".codex", "config.toml"])
  let cache = Node.join([home(), ".cache", "claude-dashboard", "codex-model-cache.json"])
  let inConfig = try modelAs->RegExp.test(Node.readFileSync(config)) catch {
  | _ => false
  }
  inConfig || try {
    let modified = Stale_jobs.modified(config)->Option.getOr(0.)
    switch Payload.parse(Node.readFileSync(cache)) {
    | Some(found) =>
      found->Payload.text("model")->Option.isSome &&
        found->Dict.get("configMtime") == Some(JSON.Number(modified))
    | None => false
    }
  } catch {
  | _ => false
  }
}

let measure = () =>
  if !modelKnown() {
    ""
  } else {
    let result = Node.spawnSync(
      reader,
      [Node.join([home(), script]), "--json"],
      {encoding: "utf8", timeout: 20000},
    )
    result.status->Nullable.toOption == Some(0) ? result.stdout->Nullable.getOr("") : ""
  }

let warning = "Warning from hooks/gates/codex_usage.res: Codex's quota could not be read, either because check-usage failed or because it has no model on record and would spend a model call to find one. This Codex run was let through unchecked."

/** The exit status the harness reads, 2 refusing a Codex run while Codex is limited. */
let refuse = (payload: Payload.t, ~measure=measure): int =>
  if !runs(Payload.command(payload)) {
    0
  } else {
    switch read(measure()) {
    | Free => 0
    | Limited(resets) =>
      Console.error(
        `Command refused by hooks/gates/codex_usage.res: Codex has no quota, a window reads 100 percent used, and it resets at ${resets}.\n` ++
        "Use Claude for this work until then.\n" ++ "The rule: codex-quota in model/rules/delegation.res, and docs/agents/delegation.md, \"Codex comes first while it has quota\"",
      )
      2
    | Unknown =>
      Console.log(
        JSON.stringify(
          JSON.Object(
            Dict.fromArray([
              (
                "hookSpecificOutput",
                JSON.Object(
                  Dict.fromArray([
                    ("hookEventName", JSON.String("PreToolUse")),
                    ("additionalContext", JSON.String(warning)),
                  ]),
                ),
              ),
            ]),
          ),
        ),
      )
      0
    }
  }
