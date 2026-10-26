/** What a create is told to name and how a place it names is judged, for `Placed`. */
/** What a create is told to name. */
let told = Toolchain.places->Array.join(" or ")

/** Whether `value` is a place a create may name. */
let passes = value => Toolchain.places->Array.includes(value)

/** A create in a shell line, its words apart by space, or quoted apart as an argv is. */
let creating = /\b(d1[\s\x22\x27,]+create|r2[\s\x22\x27,]+bucket[\s\x22\x27,]+create)\b/

/** A name bound by `let` or `const`, its value where a string literal alone gives it. */
type binding = {file: string, name: string, value: option<string>}

/** Where a create is placed, by a literal, by a name bound to one, or by what a run decides. */
type place = Literal(string) | Bound(string, binding) | Open

/** The finding on a create, by the place it names, or that it names none. */
let named = (~value=?, ~bound=?, what) =>
  switch (value, bound) {
  | (None, _) => `${what} names no --location; add --location ${told}`
  | (Some(value), None) => `${what} names --location ${value}; ${told} alone`
  | (Some(value), Some((name, file))) =>
    `${what} names --location ${name}, bound to ${value} in ${file}; ${told} alone`
  }

/** The finding on a create placed at `place`, none where it may be. */
let judged = (place, ~what) =>
  switch place {
  | Literal(value) => passes(value) ? None : Some(named(what, ~value))
  | Bound(name, {file, value: Some(value)}) =>
    passes(value) ? None : Some(named(what, ~value, ~bound=(name, file)))
  | Bound(_, _) | Open => None
  }
