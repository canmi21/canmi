/** What a TLC configuration holds and what its output says, kept apart from running TLC. */
type expected = Invariant(string) | Property(string)

type item =
  | Other(string)
  | Checked(string, array<string>)

let isChecking = word => ["INVARIANT", "INVARIANTS", "PROPERTY", "PROPERTIES"]->Array.includes(word)

let words = line => line->String.trim->String.split(" ")->Array.filter(word => word != "")

/** A configuration as its lines, each INVARIANT or PROPERTY section held with its names. */
let parse = config => {
  let items = []
  let open_ = ref(false)
  config
  ->String.split("\n")
  ->Array.forEach(line => {
    let indented = line->String.startsWith("\t") || line->String.startsWith(" ")
    let first = line->words->Array.get(0)->Option.getOr("")
    if open_.contents && (indented || String.trim(line) == "") {
      if String.trim(line) != "" {
        switch items->Array.pop {
        | Some(Checked(keyword, names)) =>
          items->Array.push(Checked(keyword, [...names, String.trim(line)]))
        | Some(other) => items->Array.push(other)
        | None => ()
        }
      }
    } else if !indented && isChecking(first) {
      items->Array.push(Checked(first, line->words->Array.slice(~start=1)))
      open_ := true
    } else {
      items->Array.push(Other(line))
      open_ := false
    }
  })
  items
}

let render = items =>
  items
  ->Array.flatMap(item =>
    switch item {
    | Other(line) => [line]
    | Checked(keyword, names) => [keyword, ...names->Array.map(name => `\t${name}`)]
    }
  )
  ->Array.join("\n")

/** Whether a checked name is an invariant or a property, as the configuration lists it. */
let expectedOf = (config, name) =>
  parse(config)->Array.findMap(item =>
    switch item {
    | Checked(keyword, names) if names->Array.includes(name) =>
      Some(keyword->String.startsWith("INVARIANT") ? Invariant(name) : Property(name))
    | _ => None
    }
  )

/** The configuration without the named checks, a section left empty gone with them. */
let without = (config, dropped) =>
  parse(config)
  ->Array.filterMap(item =>
    switch item {
    | Checked(keyword, names) =>
      let kept = names->Array.filter(name => !(dropped->Array.includes(name)))
      kept == [] ? None : Some(Checked(keyword, kept))
    | other => Some(other)
    }
  )
  ->render

/** The configuration with every check replaced by the ones asked for. */
let asking = (config, ~invariants, ~properties) => {
  let kept = parse(config)->Array.filter(item =>
    switch item {
    | Checked(_) => false
    | Other(_) => true
    }
  )
  let asked =
    [
      invariants == [] ? [] : [Checked("INVARIANT", invariants)],
      properties == [] ? [] : [Checked("PROPERTY", properties)],
    ]->Array.flat
  [...kept, ...asked]->render
}

let askingFor = (config, expected) =>
  switch expected {
  | Invariant(name) => asking(config, ~invariants=[name], ~properties=[])
  | Property(name) => asking(config, ~invariants=[], ~properties=[name])
  }

let nameOf = expected =>
  switch expected {
  | Invariant(name) | Property(name) => name
  }

/** A switch's constant set TRUE, or None where the configuration does not declare it. */
let switchedOn = (config, flag) => {
  let off = `${flag} = FALSE`
  config->String.includes(off) ? Some(config->String.replace(off, `${flag} = TRUE`)) : None
}

let distinct = out =>
  switch /, ([0-9]+) distinct states found, /->RegExp.exec(out) {
  | Some(found) =>
    found->RegExp.Result.matches->Array.get(0)->Option.flatMap(x => x)->Option.getOr("?")
  | None => "?"
  }

let passed = out => out->String.includes("Model checking completed. No error has been found.")

let broke = (out, expected) =>
  switch expected {
  | Invariant(name) => out->String.includes(`Invariant ${name} is violated`)
  | Property(name) =>
    out->String.includes(`Action property ${name} is violated`) ||
    out->String.includes(`Temporal properties were violated`) ||
    out->String.includes(`Error: The action of property ${name}`)
  }
