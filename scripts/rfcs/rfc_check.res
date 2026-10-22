/**
 * The rfcs part of check, every RFC of an id space held to RFC 2ut6h as one set, each file named
 * as the format says, its id and place its own in the space, its front, body and graph in form.
 */
type entry = {file: Rfc_spaces.file, text: string}

/** A problem, and the files it concerns, so one repository's check reports only its own. */
type problem = {concerns: array<string>, says: string}

let shape = "docs/rfcs/<area>/<yyyy>-<mmdd>-<nn>-<slug>-<id>.md"

/**
 * Every problem of one space's RFCs; `exists` says whether a commit is held, None where its
 * repository is not cloned, and `repos` are the names a commit may give.
 */
let held = (
  entries: array<entry>,
  ~strays: array<string>,
  ~areas: array<string>,
  ~repos: array<string>,
  ~exists: (string, string) => option<bool>,
): array<problem> => {
  let problems = strays->Array.map(path => {
    concerns: [path],
    says: `${Rfc_spaces.relative(path)}: not an RFC; the name is ${shape}`,
  })
  let say = (file: Rfc_spaces.file, says) =>
    problems->Array.push({concerns: [file.path], says: `${file.where}: ${says}`})
  areas->Array.forEach(area =>
    if !(Rfc_name.area->RegExp.test(area)) {
      problems->Array.push({concerns: [], says: `area ${area} is not lowercase words and hyphens`})
    }
  )
  let byId: Map.t<string, entry> = Map.make()
  let byPlace: Map.t<string, Rfc_spaces.file> = Map.make()
  entries->Array.forEach(({file} as entry) => {
    if areas->Array.includes(file.id) {
      say(file, `id ${file.id} is also an area's name`)
    }
    switch byId->Map.get(file.id) {
    | Some(holder) =>
      problems->Array.push({
        concerns: [file.path, holder.file.path],
        says: `${file.where}: id ${file.id} is also ${holder.file.where}'s`,
      })
    | None => byId->Map.set(file.id, entry)
    }
    let place = Rfc_name.place(file.day, file.order)
    switch byPlace->Map.get(place) {
    | Some(holder) =>
      problems->Array.push({
        concerns: [file.path, holder.path],
        says: `${file.where}: ${place} is also ${holder.where}'s place`,
      })
    | None => byPlace->Map.set(place, file)
    }
  })
  // What one RFC may name depends on where the others stand, so every front is read first.
  let fronts: Map.t<string, Rfc_record.front> = Map.make()
  entries->Array.forEach(({file, text}) =>
    switch Rfc_record.readFront(text) {
    | (Some(front), _) if !(fronts->Map.has(file.id)) => fronts->Map.set(file.id, front)
    | _ => ()
    }
  )
  let graph: Rfc_graph.t = Map.make()
  fronts->Map.forEachWithKey((front, id) =>
    graph->Map.set(id, {status: front.status, blockedBy: front.blockedBy})
  )
  Rfc_graph.cycles(graph)->Array.forEach(cycle =>
    problems->Array.push({
      concerns: cycle->Array.filterMap(id =>
        byId->Map.get(id)->Option.map(entry => entry.file.path)
      ),
      says: `blocked-by makes a cycle: ${cycle->Array.join(" -> ")}`,
    })
  )
  entries->Array.forEach(({file, text}) => {
    let (front, found) = Rfc_record.readFront(text)
    let body = Rfc_record.body(text)
    let status = front->Option.map(front => front.status)
    let own = Array.concat(found, Rfc_record.checkSections(body, ~status))
    own->Array.pushMany(Rfc_record.checkPlain(body))
    switch front {
    | Some(front) =>
      own->Array.pushMany(Rfc_record.checkStatus(front))
      own->Array.pushMany(Rfc_private.check(`${front.title}\n${body}`))
      front.supersedes->Array.forEach(id =>
        switch byId->Map.get(id) {
        | None => own->Array.push(`supersedes ${id}, which no RFC of its id space holds`)
        | Some(earlier)
          if Rfc_name.place(earlier.file.day, earlier.file.order) >=
          Rfc_name.place(file.day, file.order) =>
          own->Array.push(`supersedes ${id}, which is not earlier`)
        | Some(_) =>
          switch fronts->Map.get(id) {
          | Some({status: "landed"}) => ()
          | Some({status}) => own->Array.push(`supersedes ${id}, which is ${status}`)
          | None => own->Array.push(`supersedes ${id}, which is out of form`)
          }
        }
      )
      own->Array.pushMany(Rfc_graph.checkBlockers(file.id, graph))
      front.commits->Array.forEach(commit =>
        switch commit->String.split("@") {
        | [repo, _] if Planning.retired->Array.includes(repo) => ()
        | [repo, _] if !(repos->Array.includes(repo)) =>
          own->Array.push(`names ${commit}, whose repository repos/registry.toml does not list`)
        | [repo, hash] if exists(repo, hash) == Some(false) =>
          own->Array.push(`names ${commit}, which its repository does not hold`)
        | _ => ()
        }
      )
    | None => own->Array.pushMany(Rfc_private.check(body))
    }
    own->Array.forEach(says => say(file, says))
  })
  problems
}

/** Whether `repo` holds `hash`, None where it is not cloned here to ask. */
let exists = (repo, hash) => {
  let checkout = Rfc_spaces.checkout(repo)
  if !Node.existsSync(Node.join([checkout, ".jj"])) {
    None
  } else {
    let asked = Node.spawnSync(
      "jj",
      ["--ignore-working-copy", "-R", checkout, "log", "--no-graph", "-r", hash, "-T", "\"\""],
      {stdio: "ignore"},
    )
    Some(asked.status->Nullable.toOption == Some(0))
  }
}

/** Every problem of `space`, read from disk. */
let space = (space): array<problem> => {
  let {files, strays, areas}: Rfc_spaces.read = Rfc_spaces.read(space)
  held(
    files->Array.map(file => {file, text: Node.readFileSync(file.path)}),
    ~strays,
    ~areas,
    ~repos=Array.concat([Planning.workspaceSpace], Registry.paths()),
    ~exists,
  )
}

/** What the check reports for `repo`, its files held within its whole space, or nothing. */
let repository = (repo): array<string> =>
  switch Rfc_spaces.spaceOf(repo) {
  | None => []
  | Some(named) =>
    let directory = Node.join([Rfc_spaces.checkout(repo), Planning.rfcDirectory])
    let inside = path => path->String.startsWith(directory ++ Node.sep)
    space(named)
    ->Array.filter(problem =>
      problem.concerns == [] || problem.concerns->Array.some(path => inside(path))
    )
    ->Array.map(problem => problem.says)
  }
