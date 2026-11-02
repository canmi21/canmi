/**
 * The rfcs part of check, every RFC of an id space held to RFC 2ut6h as one set, each file named
 * as the format says, its id and place its own in the space, its front, body and graph in form.
 */
type entry = {file: Rfc_spaces.file, text: string}

/** A problem, and the files it concerns, so one repository's check reports only its own. */
type problem = {concerns: array<string>, says: string}

let shape = "docs/rfcs/[<area>/]<yyyy>-<mmdd>-<slug>-<id>.md"

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
  ~inTree: (string, string) => bool=(_, _) => true,
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
  // A repository's RFCs sit flat while they number at most Layout.widest, and past that in areas.
  let counts: Map.t<string, int> = Map.make()
  entries->Array.forEach(({file}) =>
    counts->Map.set(file.repo, counts->Map.get(file.repo)->Option.getOr(0) + 1)
  )
  let asked: Map.t<string, bool> = Map.make()
  let inTree = (repo, area) => {
    let key = `${repo}/${area}`
    switch asked->Map.get(key) {
    | Some(answer) => answer
    | None =>
      let answer = inTree(repo, area)
      asked->Map.set(key, answer)
      answer
    }
  }
  let byId: Map.t<string, entry> = Map.make()
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
    let split = counts->Map.get(file.repo)->Option.getOr(0) > Layout.widest
    if split && file.area == "" {
      say(
        file,
        `${file.repo} holds more than ${Int.toString(
            Layout.widest,
          )} RFCs, so each stands in an area`,
      )
    } else if !split && file.area != "" {
      say(
        file,
        `${file.repo} holds at most ${Int.toString(Layout.widest)} RFCs, so they stand flat`,
      )
    } else if file.area != "" && !inTree(file.repo, file.area) {
      say(file, `area ${file.area} is no directory of ${file.repo}'s own tree`)
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
    let newForm = file.day >= Planning.newFormFrom && !(Planning.oldForm->Array.includes(file.id))
    let own = Array.concat(found, Rfc_record.checkSections(body, ~status, ~newForm))
    if newForm {
      own->Array.pushMany(Rfc_record.checkNewForm(text, ~status))
    }
    own->Array.pushMany(Rfc_record.checkPlain(body))
    switch front {
    | Some(front) =>
      if !newForm {
        own->Array.pushMany(Rfc_record.checkStatus(front))
      }
      own->Array.pushMany(Rfc_private.check(`${front.title}\n${body}`))
      front.supersedes->Array.forEach(id =>
        switch byId->Map.get(id) {
        | None => own->Array.push(`supersedes ${id}, which no RFC of its id space holds`)
        // A name holds no order within a day, so a superseded RFC of the same day is allowed.
        | Some(earlier) if earlier.file.day > file.day =>
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
    ~inTree=(repo, area) => Rfc_spaces.tree(repo)->Array.includes(area),
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
