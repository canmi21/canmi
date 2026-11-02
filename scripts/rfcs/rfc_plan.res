/**
 * `plan [space]`, what is left in one id space or in every one, read off the RFCs, the open ones
 * nothing open blocks and then each of the rest behind the longest chain it waits on, those with a
 * step underway first. RFC p992n.
 */
type shown = {front: Rfc_record.front, at: string}

/** One space's plan, as the lines it prints. */
let lines = (space): array<string> => {
  let shown: Map.t<string, shown> = Map.make()
  Rfc_spaces.read(space).files->Array.forEach(file =>
    switch Rfc_record.readFront(Node.readFileSync(file.path)) {
    | (Some(front), _) =>
      shown->Map.set(
        file.id,
        {front, at: file.area == "" ? file.repo : `${file.repo}/${file.area}`},
      )
    | (None, _) => ()
    }
  )
  let graph: Rfc_graph.t = Map.make()
  shown->Map.forEachWithKey(({front}, id) =>
    graph->Map.set(id, {status: front.status, blockedBy: front.blockedBy})
  )
  let wide =
    shown
    ->Map.values
    ->Iterator.toArray
    ->Array.reduce(0, (most, {at}) => Math.Int.max(most, at->String.length))
  let line = id =>
    switch shown->Map.get(id) {
    | Some({front, at}) =>
      `${id}  ${front.status->String.padEnd(8, " ")}  ${at->String.padEnd(
          wide,
          " ",
        )}  ${front.name}`
    | None => id
    }
  let now = Rfc_graph.ready(graph)
  let underway =
    shown
    ->Map.entries
    ->Iterator.toArray
    ->Array.filterMap(((id, {front})) => front.underway->Option.map(step => (id, step)))
    ->Array.toSorted(((a, _), (b, _)) => String.compare(a, b))
  let waiting =
    graph
    ->Map.entries
    ->Iterator.toArray
    ->Array.filterMap(((id, node)) =>
      Rfc_graph.isOpen(node.status) && !(now->Array.includes(id))
        ? Some(Rfc_graph.chainOf(id, graph))
        : None
    )
    ->Array.toSorted((a, b) => Int.toFloat(b->Array.length - a->Array.length))
  Array.flat([
    underway == [] ? [] : [`${space}, underway (${Int.toString(underway->Array.length)}):`],
    underway->Array.flatMap(((id, step)) => [`  ${line(id)}`, `      now: ${step}`]),
    underway == [] ? [] : [""],
    [`${space}, ready, nothing open blocks them (${Int.toString(now->Array.length)}):`],
    now->Array.map(id => `  ${line(id)}`),
    [
      "",
      `${space}, waiting (${Int.toString(
          waiting->Array.length,
        )}), each after the longest chain ahead of it:`,
    ],
    waiting->Array.flatMap(chain => [
      `  ${line(chain->Array.at(-1)->Option.getOr(""))}`,
      `      ${chain->Array.join(" -> ")}`,
    ]),
  ])
}

/** An item's words cut at a word near `width`, for one line. */
let brief = (text, ~width=96) =>
  if text->String.length <= width {
    text
  } else {
    let cut = text->String.slice(~start=0, ~end=width)
    let at = cut->String.lastIndexOf(" ")
    `${cut->String.slice(~start=0, ~end=at > 0 ? at : width)} ...`
  }

/**
 * The plans of the workspace and of every repository by where they stand, and what is done on
 * request.
 */
let work = (~done): array<string> => {
  let (sources, errors) = Repo_plan.load()
  let merged = Repo_plan.merge(sources)
  let items = merged->Array.map(({item}) => item)
  let entryOf = (item: Work.item) => merged->Array.find(entry => entry.item.id == item.id)
  let hidden = (item: Work.item) =>
    Repo_plan.leaves() && entryOf(item)->Option.mapOr(false, entry => entry.isPrivate)
  let mark = (item: Work.item) =>
    entryOf(item)->Option.mapOr("", entry => entry.isPrivate ? " [private]" : "")
  let name = (item: Work.item) => Repo_plan.label(item.id)
  let committed = Plan.onMain
  let state = item => Plan.stateOf(items, item, ~committed)
  let in_ = pick => items->Array.filter(item => pick(state(item)))
  let line = (item: Work.item, ~extra="") =>
    hidden(item)
      ? `  ${name(item)}${mark(item)}  withheld`
      : `  ${name(item)}${mark(item)}  ${brief(item.says)}${extra}`
  let section = (title, lines) =>
    Array.flat([[`${title} (${Int.toString(lines->Array.length)}):`], lines, [""]])
  let under = in_(s => s == Plan.Under)
  let ready = in_(s => s == Plan.Ready)
  let behind = in_(s =>
    switch s {
    | Plan.Behind(_) => true
    | _ => false
    }
  )
  let awaits = in_(s =>
    switch s {
    | Plan.Awaits(_) => true
    | _ => false
    }
  )
  let finished = in_(s => s == Plan.Done)
  let why = (item: Work.item) =>
    switch state(item) {
    | Plan.Behind(ids) => `; after ${ids->Array.map(Repo_plan.label)->Array.join(", ")}`
    | Plan.Awaits(Author) => "; waits on the author"
    | Plan.Awaits(Closes(id)) => `; waits on ${id}`
    | _ => ""
    }
  let held = (item: Work.item) =>
    switch item.holds {
    | Work.Holds(part) => `held by the part ${part}`
    | Work.Committed({repo, commit}) =>
      `${commit->String.slice(~start=0, ~end=8)} on the main of ${repo}`
    | Work.Observed({at, what}) => `observed ${at}, ${what}`
    | Work.Owes(_) | Work.Landing(_) => ""
    }
  let owed = Plan.pendingRules(Rules.all)
  let passed = Repo_plan.passedOver(sources, ~skipped=Waiting.skipped)
  let aside = Array.concat(errors, passed->Array.map(line => `  ${line}`))
  let local =
    merged->Array.some(entry => entry.isPrivate)
      ? ["plan, items marked [private] are local, never copied into anything public", ""]
      : []
  Array.concat(aside == [] ? [] : section("plan, passed over", aside), local)->Array.concat(
    done
      ? section(
          "plan, done",
          finished->Array.map(item =>
            `  ${name(item)}${mark(item)}  ${hidden(item) ? "withheld" : held(item)}`
          ),
        )
      : Array.flat([
          section("plan, under way, its check warning", under->Array.map(item => line(item))),
          section("plan, ready, nothing before it undone", ready->Array.map(item => line(item))),
          section(
            "plan, waiting on the items before them",
            behind->Array.map(item => line(item, ~extra=why(item))),
          ),
          section(
            "plan, waiting on a moment",
            awaits->Array.map(item => line(item, ~extra=why(item))),
          ),
          section(
            "plan, pending rules, ready, each owed a check",
            owed->Array.map(((name, needs)) => `  ${name}  owed: ${brief(needs)}`),
          ),
          [
            `plan, done: ${Int.toString(finished->Array.length)}; mise run plan --done lists them`,
            "",
          ],
        ]),
  )
}

let main = () => {
  let known = Rfc_spaces.names()
  let given = Node.args()
  let done = given->Array.includes("--done")
  let asked = given->Array.filter(arg => arg != "--done")
  let chosen = switch asked {
  | [] => known
  | [space] if known->Array.includes(space) => [space]
  | _ =>
    Console.error(
      `usage: mise run plan [space] [--done]; the spaces are ${known->Array.join(", ")}`,
    )
    Node.exit(2)
  }
  if asked == [] {
    work(~done)->Array.forEach(line => Console.log(line))
  }
  if !done {
    Console.log("RFCs, drafts and accepted ones, the accepted not yet read against the code:")
    chosen->Array.forEachWithIndex((space, at) => {
      if at > 0 {
        Console.log("")
      }
      lines(space)->Array.forEach(line => Console.log(line))
    })
    Released.line()->Option.forEach(line => Console.log(`\n${line}`))
  }
}

if Node.isMain {
  main()
}
