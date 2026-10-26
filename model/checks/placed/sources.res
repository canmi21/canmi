/** The judgment of a create in a source's arrays and strings, for `Placed`. */
open Placing
open Quoting
open Shells

/** A create in a source, its consecutive strings in an array or a list. */
let created = /([\x22\x27\x60])(?:d1\1\s*,\s*\1create|r2\1\s*,\s*\1bucket\1\s*,\s*\1create)\1/g

/** The quotes a source's strings open with, ReScript's own lacking the single one. */
let quotesOf = file => file->String.endsWith(".res") ? "\"`" : "\"'`"

/** A `let`, `const` or `var`, its name and what it binds. */
let binds = /^\s*(?:export\s+)?(?:let|const|var)\s+([\w$][\w$']*)\s*(?::[^=\n]*)?=(.*)$/gm

/** Each `let`, `const` or `var` a blanked source holds, by its name and any literal it binds. */
let bindings = (text, ~file): array<binding> =>
  all(binds, text)->Array.filterMap(result =>
    switch result->RegExp.Result.matches {
    | [Some(name), Some(bound)] =>
      let bound = bound->String.trim->String.replaceRegExp(/;$/, "")->String.trim
      Some({file, name, value: quoted(bound)->Option.flatMap(fixed)})
    | _ => None
    }
  )

/** The module a source `file` is, as another names it. */
let moduleOf = file => {
  let base = Node.basename(file)->String.replaceRegExp(/\.(?:res|mjs|js|ts)$/, "")
  `${base->String.charAt(0)->String.toUpperCase}${base->String.slice(~start=1)}`
}

/** The modules a blanked source opens, each by its last name. */
let opens = text =>
  all(/^[ \t]*open!?\s+([A-Z][\w.]*)/gm, text)->Array.filterMap(result =>
    switch result->RegExp.Result.matches {
    | [Some(path)] => path->String.split(".")->Array.at(-1)
    | _ => None
    }
  )

/** What `id` is bound to, in `file` and then the modules it opens, or `Mod.x` in mod's file. */
let resolved = (id, ~file, ~modules, ~bound: array<binding>): option<binding> => {
  let parts = id->String.split(".")
  let name = parts->Array.at(-1)->Option.getOr(id)
  let within = owns => bound->Array.find(binding => binding.name == name && owns(binding.file))
  switch parts->Array.at(-2) {
  | Some(owner) => within(other => moduleOf(other) == owner)
  | None =>
    switch within(other => other == file) {
    | Some(binding) => Some(binding)
    | None => modules->Array.findMap(owner => within(other => moduleOf(other) == owner))
    }
  }
}

/** Where one element after `--location` places a create, a name by what it is bound to. */
let valueOf = (element, ~resolve) =>
  switch quoted(element) {
  | Some(literal) => fixed(literal)->Option.mapOr(Open, value => Literal(value))
  | None if /^[A-Za-z_$][\w$.']*$/->RegExp.test(element) =>
    switch resolve(element) {
    | Some({value: Some(_)} as binding) => Bound(element, binding)
    | _ => Open
    }
  | None => Open
  }

/** Where the elements of one array place a create, if they name `--location` at all. */
let placeIn = (held: array<string>, ~resolve): option<place> =>
  switch held->Array.findIndex(element =>
    quoted(element)->Option.map(((_, inner)) => inner) == Some("--location")
  ) {
  | -1 =>
    held->Array.findMap(element =>
      switch quoted(element) {
      | Some((mark, inner)) if inner->String.startsWith("--location=") =>
        let value = (mark, inner->String.slice(~start=String.length("--location=")))
        Some(fixed(value)->Option.mapOr(Open, value => Literal(value)))
      | _ => None
      }
    )
  | at => Some(held->Array.get(at + 1)->Option.mapOr(Open, element => valueOf(element, ~resolve)))
  }

/** The line after a definition, where the next one begins. */
let defined = /\n(?=(?:let|const|function|export|type|module|open|include|external)\b|@)/

/** Where the function `name` a blanked source defines places what it spreads, if it does. */
let spreadPlace = (text, name, ~quotes, ~resolve) => {
  let escaped = name->String.replaceAll("$", "\\$")
  let definition = RegExp.fromString(
    `^[ \\t]*(?:export\\s+)?(?:let|const|function)\\s+(?:rec\\s+)?${escaped}\\b`,
    ~flags="m",
  )
  definition
  ->RegExp.exec(text)
  ->Option.flatMap(result => {
    let begins = result->RegExp.Result.index
    let rest = text->String.slice(~start=begins)
    let body = switch defined->RegExp.exec(rest) {
    | Some(found) => rest->String.slice(~start=0, ~end=found->RegExp.Result.index)
    | None => rest
    }
    let flagged = /[\x22\x27\x60]--location[=\x22\x27\x60]/
    flagged
    ->RegExp.exec(body)
    ->Option.flatMap(flag => containerAt(text, begins + flag->RegExp.Result.index, ~quotes))
    ->Option.flatMap(held => placeIn(held, ~resolve))
  })
}

/** What one array or list of a create leaves unplaced, a spread placing it as its function does. */
let unplaced = (held, ~what, ~text, ~quotes, ~resolve) =>
  switch placeIn(held, ~resolve) {
  | Some(place) => judged(place, ~what)
  | None =>
    let spread = held->Array.filterMap(element =>
      switch /^\.\.\.\s*([A-Za-z_$][\w$.]*)\s*\(/->RegExp.exec(element) {
      | Some(result) =>
        switch result->RegExp.Result.matches {
        | [Some(call)] =>
          let name = call->String.split(".")->Array.at(-1)->Option.getOr(call)
          spreadPlace(text, name, ~quotes, ~resolve)
        | _ => None
        }
      | None => None
      }
    )
    spread == [] ? Some(named(what)) : spread->Array.findMap(place => judged(place, ~what))
  }

/** Each create in one blanked source, `file` naming it, by its line and what it leaves unplaced. */
let codeJudged = (text, ~file, ~bound): array<(int, option<string>)> => {
  let quotes = quotesOf(file)
  let modules = opens(text)
  let own = bindings(text, ~file)
  let bound = Array.concat(own, bound->Array.filter(binding => binding.file != file))
  let resolve = id => resolved(id, ~file, ~modules, ~bound)
  let arrays = all(created, text)->Array.filterMap(result => {
    let at = result->RegExp.Result.index
    let what = result->RegExp.Result.fullMatch->String.replaceRegExp(/\W+/g, " ")->String.trim
    containerAt(text, at, ~quotes)->Option.map(held => (
      lineOf(text, at),
      unplaced(held, ~what, ~text, ~quotes, ~resolve),
    ))
  })
  let lines =
    literals(text, ~quotes)->Array.flatMap(((at, inner)) =>
      creating->RegExp.test(inner)
        ? shellJudged(inner, ~file)->Array.map(((line, said)) => (
            lineOf(text, at) + line - 1,
            said,
          ))
        : []
    )
  Array.concat(arrays, lines)
}

/** Each create in one source, `file` naming it, that names no place it may name. */
let source = (text, ~file, ~bound) =>
  codeJudged(blanked(text, ~quotes=quotesOf(file)), ~file, ~bound)->shown(~file)
