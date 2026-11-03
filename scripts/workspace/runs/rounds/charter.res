/** A charter's steps and which are ready, docs/agents/threads.md. */
type step = {id: string, after: array<string>}

let stepStart = /^(\d+[a-z]*)\.\s/
let afterLine = /^\s*after:\s*(.*?)\s*$/

let group = (found, at) => found->RegExp.Result.matches->Array.get(at)->Option.flatMap(x => x)

/** Each step that says what it comes after; one that says nothing is no step of this shape. */
let stepsOf = (text: string): array<step> => {
  let steps = []
  let current = ref(None)
  text
  ->String.split("\n")
  ->Array.forEach(line =>
    switch RegExp.exec(stepStart, line) {
    | Some(found) => current := group(found, 0)
    | None =>
      switch (RegExp.exec(afterLine, line), current.contents) {
      | (Some(found), Some(id)) =>
        let named = group(found, 0)->Option.getOr("")
        steps->Array.push({
          id,
          after: named == "none" || named == ""
            ? []
            : named->String.splitByRegExp(/\s*,\s*/)->Array.filterMap(x => x),
        })
        current := None
      | _ => ()
      }
    }
  )
  steps
}

/** What keeps a charter from being read as written, a reference to no step among it. */
let problemsOf = (text: string, ~greens: array<string>) => {
  let steps = stepsOf(text)
  let ids = steps->Array.map(step => step.id)
  let numbered =
    text
    ->String.split("\n")
    ->Array.filterMap(line =>
      RegExp.exec(stepStart, line)->Option.flatMap(found => group(found, 0))
    )
  Array.flat([
    numbered
    ->Array.filter(id => !(ids->Array.includes(id)))
    ->Array.map(id => `step ${id} has no \`after:\` line of its own`),
    steps->Array.flatMap(step =>
      step.after
      ->Array.filter(id => !(ids->Array.includes(id)))
      ->Array.map(id => `step ${step.id} comes after \`${id}\`, which is no step`)
    ),
    ids == []
      ? []
      : greens
        ->Array.filter(id => !(ids->Array.includes(id)))
        ->Array.map(id => `green names step ${id}, which is no step`),
  ])
}

/** A thread's charter problems, one that cannot be read being one. */
let problems = (name, ~records: array<Figures.record>) =>
  try {
    let file = Node.join([Figures.directory(name), "charter.md"])
    let greens = records->Array.filterMap(one =>
      switch one {
      | Green({step}) => Some(step)
      | _ => None
      }
    )
    Node.existsSync(file) ? problemsOf(Node.readFileSync(file), ~greens) : ["it has no charter"]
  } catch {
  | _ => ["its charter cannot be read"]
  }

/** The steps of a thread's charter, none where it has no charter or an older shape. */
let steps = name => {
  let file = Node.join([Figures.directory(name), "charter.md"])
  Node.existsSync(file) ? stepsOf(Node.readFileSync(file)) : []
}

/** Each step's first green at or before `at`. */
let greenBy = (records: array<Figures.record>, ~at) => {
  let found = Dict.make()
  records->Array.forEach(one =>
    switch one {
    | Green({step, at: when_}) if when_ <= at && found->Dict.get(step) == None =>
      found->Dict.set(step, when_)
    | _ => ()
    }
  )
  found
}

/** Each step ready at `at`, not green with all it comes after green, and since when. */
let ready = (steps: array<step>, records, ~at) => {
  let green = greenBy(records, ~at)
  steps->Array.filterMap(step =>
    green->Dict.get(step.id) == None && step.after->Array.every(id => green->Dict.get(id) != None)
      ? Some((
          step,
          step.after->Array.reduce(0., (latest, id) =>
            Math.max(latest, green->Dict.get(id)->Option.getOr(0.))
          ),
        ))
      : None
  )
}
