/** The guard a file listed in `placedAtRunTime` places its creates through, read for `placed`. */
open Quoting

/** `text` with every string literal blanked, so a word inside one is never read as code. */
let codeOnly = text =>
  literals(text, ~quotes="\"'`")->Array.reduce(text, (code, (at, inner)) => {
    let stop = at + String.length(inner) + 2
    `${code->String.slice(~start=0, ~end=at)}${String.repeat(" ", stop - at)}${code->String.slice(
        ~start=stop,
      )}`
  })

/** The modules `text` opens, names or imports, where its guard may be bound. */
let referenced = text => {
  let code = codeOnly(text)
  let named =
    all(/\b([A-Z][\w]*)\s*\./g, code)->Array.filterMap(result =>
      result->RegExp.Result.matches->Array.get(0)->Option.flatMap(value => value)
    )
  let imported = all(
    /\bimport\s+(?:[^;\n]*?\s+from\s+)?[\x22\x27]([^\x22\x27]+)[\x22\x27]/g,
    text,
  )->Array.filterMap(result => {
    let at = result->RegExp.Result.index
    code->String.slice(~start=at)->String.startsWith("import")
      ? result
        ->RegExp.Result.matches
        ->Array.get(0)
        ->Option.flatMap(value => value)
        ->Option.map(Sources.moduleOf)
      : None
  })
  Array.concatMany(Sources.opens(code), [named, imported])
}

/** Whether `text` binds `locations` to a literal list of places alone, none where it binds none. */
let locations = (text, ~quotes) =>
  all(Sources.binds, codeOnly(text))->Array.findMap(result =>
    switch result->RegExp.Result.matches {
    | [Some("locations"), Some(_)] =>
      let rest = text->String.slice(~start=result->RegExp.Result.index)
      let body = switch Sources.defined->RegExp.exec(rest) {
      | Some(next) => rest->String.slice(~start=0, ~end=next->RegExp.Result.index)
      | None => rest
      }
      Some(
        switch /^\s*(?:export\s+)?(?:let|const|var)\s+locations\s*(?::[^=\n]*)?=\s*\[/->RegExp.exec(
          body,
        ) {
        | Some(array) =>
          let start = array->RegExp.Result.index + String.length(array->RegExp.Result.fullMatch)
          let stop = closing(body, start, ~quotes)
          let tail = body->String.slice(~start=stop + 1)->String.trim
          body->String.charAt(stop) == "]" &&
          (tail == "" || tail == ";") &&
          elements(body, ~start, ~stop, ~quotes)->Array.every(element =>
            quoted(element)
            ->Option.flatMap(fixed)
            ->Option.mapOr(false, place => Toolchain.places->Array.includes(place))
          )
        | None => false
        },
      )
    | _ => None
    }
  )

/** Whether `text` filters a value by membership in `locations`, so an unset one gives none. */
let filtered = (text, ~quotes) =>
  all(/\bOption\s*\.\s*filter\s*\(/g, codeOnly(text))->Array.some(result => {
    let start = result->RegExp.Result.index + String.length(result->RegExp.Result.fullMatch)
    let stop = closing(text, start, ~quotes)
    let callback = elements(text, ~start, ~stop, ~quotes)->Array.at(-1)->Option.getOr("")
    switch /^\s*\(?\s*([a-zA-Z_]\w*)\s*\)?\s*=>\s*(.*?)\s*$/s->RegExp.exec(callback) {
    | Some(found) =>
      switch found->RegExp.Result.matches {
      | [Some(name), Some(body)] =>
        let body = body->String.replaceRegExp(/\s+/g, "")
        let body = body->String.replaceRegExp(/^\{(?:return)?|;?\}$/g, "")
        body == `locations->Array.includes(${name})` || body == `Array.includes(locations,${name})`
      | _ => false
      }
    | None => false
    }
  })

/** The guard of a listed `file`, read there or in a module of `sources` it uses, or what fails. */
let checked = (text, ~file, ~sources) => {
  let modules = referenced(text)
  let candidates = [
    (file, text),
    ...sources->Array.filter(((other, _)) =>
      other != file && modules->Array.includes(Sources.moduleOf(other))
    ),
  ]
  switch candidates->Array.findMap(((origin, text)) =>
    locations(text, ~quotes=Sources.quotesOf(origin))->Option.map(valid => (origin, text, valid))
  ) {
  | None => Error(`the guard in ${file} drifts from places; no literal locations binding`)
  | Some((origin, _, false)) => Error(`the guard in ${origin} drifts from places`)
  | Some((origin, text, true)) =>
    filtered(text, ~quotes=Sources.quotesOf(origin))
      ? Ok()
      : Error(`the guard in ${origin} does not refuse an unset value`)
  }
}
