/**
 * What blocks what among one id space's RFCs, by `blocked-by` alone, every way the graph strays
 * from RFC p992n and the order of the work read off it.
 */
type node = {status: string, blockedBy: array<string>}
type t = Map.t<string, node>

/** Still to be done, open or decided and waiting. */
let isOpen = status => status == "draft" || status == "accepted"

/** Every cycle, each once, as the ids around it with the first repeated at the end. */
let cycles = (graph: t): array<array<string>> => {
  let found = []
  let done = Set.make()
  let rec walk = (id, path: array<string>) => {
    let at = path->Array.indexOf(id)
    if at != -1 {
      found->Array.push(Array.concat(path->Array.slice(~start=at), [id]))
    } else if !(done->Set.has(id)) {
      switch graph->Map.get(id) {
      | Some(node) =>
        node.blockedBy->Array.forEach(next => walk(next, Array.concat(path, [id])))
        done->Set.add(id)
      | None => ()
      }
    }
  }
  graph->Map.keys->Iterator.toArray->Array.forEach(id => walk(id, []))
  found
}

/** Every way one RFC's blockers stray, unknown, itself, or standing where they cannot. */
let checkBlockers = (id, graph: t): array<string> =>
  switch graph->Map.get(id) {
  | None => []
  | Some(node) =>
    node.blockedBy->Array.filterMap(other =>
      switch graph->Map.get(other) {
      | _ if other == id => Some("is blocked by itself")
      | None => Some(`is blocked by ${other}, which no RFC of its id space holds`)
      | Some(blocker) if node.status == "landed" && isOpen(blocker.status) =>
        Some(`landed while ${other}, which blocks it, is ${blocker.status}`)
      | Some(blocker) if isOpen(node.status) && blocker.status == "declined" =>
        Some(`is blocked by ${other}, which was declined; drop it`)
      | Some(_) => None
      }
    )
  }

/** The open RFCs this one waits on, directly. */
let waitsOn = (id, graph: t) =>
  graph
  ->Map.get(id)
  ->Option.mapOr([], node => node.blockedBy)
  ->Array.filter(other => graph->Map.get(other)->Option.mapOr(false, node => isOpen(node.status)))

/** The open RFCs nothing open blocks, what can be taken up now. */
let ready = (graph: t): array<string> =>
  graph
  ->Map.entries
  ->Iterator.toArray
  ->Array.filterMap(((id, node)) =>
    isOpen(node.status) && waitsOn(id, graph) == [] ? Some(id) : None
  )

/** The longest chain of open RFCs an open one waits behind, itself last; the graph has no cycle. */
let rec chainOf = (id, graph: t): array<string> => {
  let longest = waitsOn(id, graph)->Array.reduce([], (longest, other) => {
    let chain = chainOf(other, graph)
    chain->Array.length > longest->Array.length ? chain : longest
  })
  Array.concat(longest, [id])
}
