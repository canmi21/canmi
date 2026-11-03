/** A charter's steps and which are ready, docs/agents/threads.md. */
type step = {id: string, after: array<string>}

let stepStart = /^(\d+[a-z]*)\.\s/
let afterLine = /^\s+after:\s*(.*?)\s*$/

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
            : named->String.splitByRegExp(/[,\s]+/)->Array.filterMap(x => x),
        })
        current := None
      | _ => ()
      }
    }
  )
  steps
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
