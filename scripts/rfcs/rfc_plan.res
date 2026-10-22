/**
 * `plan [space]`, what is left in one id space or in every one, read off the RFCs, the open ones
 * nothing open blocks and then each of the rest behind the longest chain it waits on. RFC p992n.
 */
type shown = {front: Rfc_record.front, at: string}

/** One space's plan, as the lines it prints. */
let lines = (space): array<string> => {
  let shown: Map.t<string, shown> = Map.make()
  Rfc_spaces.read(space).files->Array.forEach(file =>
    switch Rfc_record.readFront(Node.readFileSync(file.path)) {
    | (Some(front), _) => shown->Map.set(file.id, {front, at: `${file.repo}/${file.area}`})
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

let main = () => {
  let known = Rfc_spaces.names()
  let chosen = switch Node.args() {
  | [] => known
  | [space] if known->Array.includes(space) => [space]
  | _ =>
    Console.error(`usage: mise run plan [space]; the spaces are ${known->Array.join(", ")}`)
    Node.exit(2)
  }
  chosen->Array.forEachWithIndex((space, at) => {
    if at > 0 {
      Console.log("")
    }
    lines(space)->Array.forEach(line => Console.log(line))
  })
}

if Node.isMain {
  main()
}
