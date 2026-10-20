/**
 * What a file is to a build: two revisions of it compare equal here when no image built from them
 * could tell them apart. Rust source is its tokens, without comments or layout; a Dockerfile, a
 * `.dockerignore` and the image task are their lines without comments or blank ones; a declaration
 * or a crate's manifest is its parsed value. Anything else is its bytes. Read by deployable.res.
 */
/** Where a crate keeps what `cargo build` never compiles into its binary. */
let unbuiltDirectories = ["tests", "benches", "examples"]

/** A Dockerfile's parser directives, which look like comments and change the build. */
let directive = /^#\s*(syntax|check|escape)\s*=/i

/** A heredoc's opening, `<<EOF`, `<<-EOF` or with the word quoted. */
let heredoc = /<<(-?)\s*["']?([A-Za-z_][A-Za-z0-9_]*)["']?/

/** What starts a raw string, and a raw identifier, at the start of a token. */
let rawString = /(?:br|cr|r)(#*)"/y
let rawIdentifier = /r#[A-Za-z_][A-Za-z0-9_]*/y

/** A character that may continue an identifier, a keyword or a number. */
let wordCharacter = /[A-Za-z0-9_]/
let space = /\s/
let leadingDigit = /^[0-9]/
let leadingTabs = /^\t+/
let lineBreak = /\r\n|\r|\n/

let opening = ["(", "[", "{"]
let closing_ = [")", "]", "}"]
let isOpening = token => opening->Array.includes(token)
let isClosing = token => closing_->Array.includes(token)

/** Words after which `(` opens a tuple, not a call's arguments. */
let keywords = [
  "return",
  "in",
  "match",
  "if",
  "while",
  "break",
  "else",
  "let",
  "for",
  "move",
  "yield",
]

let word = character => character != "" && wordCharacter->RegExp.test(character)

/**
 * Whether `path` goes into no image at all: prose, a license, or what a crate builds only for its
 * tests, benchmarks and examples.
 */
let ignored = (path: string, ~crateDirectories: array<string>=[]): bool => {
  let name = path->String.slice(~start=path->String.lastIndexOf("/") + 1)
  name->String.endsWith(".md") ||
  name->String.startsWith("LICENSE") ||
  crateDirectories->Array.some(directory => {
    let rest =
      path->String.startsWith(`${directory}/`)
        ? path->String.slice(~start=directory->String.length + 1)
        : ""
    rest->String.includes("/") &&
      unbuiltDirectories->Array.includes(rest->String.split("/")->Array.getUnsafe(0))
  })
}

/** `pattern`, sticky, matched at `at` in `text`. */
let matchAt = (pattern, text, at) => {
  pattern->RegExp.setLastIndex(at)
  pattern->RegExp.exec(text)
}

/** The index of the bracket closing the one at `index`, or the end. */
let closingOf = (tokens: array<string>, index) => {
  let depth = ref(0)
  let found = ref(None)
  let at = ref(index)
  while found.contents == None && at.contents < tokens->Array.length {
    let token = tokens->Array.getUnsafe(at.contents)
    if isOpening(token) {
      depth := depth.contents + 1
    } else if isClosing(token) {
      depth := depth.contents - 1
      if depth.contents == 0 {
        found := Some(at.contents)
      }
    }
    at := at.contents + 1
  }
  found.contents->Option.getOr(tokens->Array.length)
}

let startsWith = (tokens: array<string>, at, run: array<string>) =>
  run->Array.everyWithIndex((token, offset) => tokens[at + offset] == Some(token))

/**
 * `tokens` with the body of every match arm and closure that is a block of one expression written
 * without its braces, `=> { x }` as `=> x,` and `|y| { x }` as `|y| x`, as rustfmt writes it once
 * it fits on a line.
 */
let unbraced = (input: array<string>) => {
  let tokens = input->Array.copy
  let at = ref(0)
  while at.contents + 1 < tokens->Array.length {
    let arm = startsWith(tokens, at.contents, ["=", ">", "{"])
    if !arm && !startsWith(tokens, at.contents, ["|", "{"]) {
      at := at.contents + 1
    } else {
      let brace = arm ? at.contents + 2 : at.contents + 1
      let end = closingOf(tokens, brace)
      let inner = tokens->Array.slice(~start=brace + 1, ~end)
      let depth = ref(0)
      let statement = ref(false)
      inner->Array.forEach(token => {
        depth := depth.contents + (isOpening(token) ? 1 : 0) - (isClosing(token) ? 1 : 0)
        statement := statement.contents || (depth.contents == 0 && token == ";")
      })
      if inner->Array.length > 0 && !statement.contents && end < tokens->Array.length {
        let comma = arm && tokens[end + 1] != Some(",") ? [","] : []
        tokens->Array.splice(
          ~start=brace,
          ~remove=end + 1 - brace,
          ~insert=Array.concat(inner, comma),
        )
      }
      at := brace
    }
  }
  tokens
}

/**
 * `tokens` without the `;` after a `return`, `break` or `continue` that ends a block, which
 * rustfmt adds when it puts the block on lines of its own and which changes nothing there.
 */
let withoutOptionalSemicolons = (tokens: array<string>) => {
  let kept = []
  let starts: array<option<int>> = []
  tokens->Array.forEachWithIndex((token, index) => {
    let after = tokens[index + 1]->Option.getOr("")
    switch (token, starts->Array.at(-1)) {
    | (";", Some(Some(start))) =>
      let ends = ["return", "break", "continue"]->Array.includes(kept[start]->Option.getOr(""))
      if !(after == "}" && ends) {
        kept->Array.push(token)
        starts->Array.set(starts->Array.length - 1, Some(kept->Array.length))
      }
    | _ =>
      kept->Array.push(token)

      // A statement begins only in a block.
      if isOpening(token) {
        starts->Array.push(token == "{" ? Some(kept->Array.length) : None)
      } else if isClosing(token) && starts->Array.length > 0 {
        starts->Array.pop->ignore
      }
    }
  })
  kept
}

/**
 * `tokens` without the commas that mean nothing: one ending a list, right before `)`, `]`, `}` or
 * `>`, and one right after a block's `}` with more to follow, as after a match arm. The comma
 * ending a tuple's parentheses with no other is kept, since it makes `(x,)` a tuple; parentheses
 * after a name, `!`, `)`, `]` or `>` are a call's, whose last comma means nothing.
 */
let withoutOptionalCommas = (tokens: array<string>) => {
  // Each open bracket: its commas so far, and whether it holds a call's arguments.
  let kept = []
  let brackets: array<(ref<int>, bool)> = []
  let closers = Array.concat(closing_, [">"])
  tokens->Array.forEachWithIndex((token, index) => {
    let before = index > 0 ? tokens->Array.getUnsafe(index - 1) : ""
    let after = tokens[index + 1]->Option.getOr("")
    let dropped = if token == "," {
      switch brackets->Array.at(-1) {
      | Some((commas, _)) => commas := commas.contents + 1
      | None => ()
      }
      before == "}" && !(closers->Array.includes(after))
    } else {
      if (isClosing(token) || token == ">") && kept->Array.at(-1) == Some(",") {
        let tupleOfOne = switch brackets->Array.at(-1) {
        | Some((commas, named)) => token == ")" && commas.contents == 1 && !named
        | None => false
        }
        if !tupleOfOne {
          kept->Array.pop->ignore
        }
      }
      false
    }
    if !dropped {
      if isOpening(token) {
        let named =
          word(before->String.charAt(0)) &&
          !(keywords->Array.includes(before)) &&
          !(leadingDigit->RegExp.test(before))
        brackets->Array.push((ref(0), named || ["!", ")", "]", ">"]->Array.includes(before)))
      } else if isClosing(token) && brackets->Array.length > 0 {
        brackets->Array.pop->ignore
      }
      kept->Array.push(token)
    }
  })
  kept
}

/**
 * The tokens of Rust source `text`, comments and whitespace dropped. A literal is kept whole, so a
 * change inside a string is a change; punctuation is one character a token, so `&&` and `& &`,
 * which rustfmt rewrites one into the other, are the same; and the commas rustfmt adds and removes
 * as it wraps a line are dropped, see `withoutOptionalCommas`.
 */
let rustTokens = (text: string): array<string> => {
  let tokens = []
  let n = text->String.length
  let i = ref(0)
  let at = index => text->String.charAt(index)
  let from = (index, prefix) => text->String.startsWithFrom(prefix, index)
  while i.contents < n {
    let c = at(i.contents)
    if space->RegExp.test(c) {
      i := i.contents + 1
    } else if from(i.contents, "//") {
      let end = text->String.indexOfFrom("\n", i.contents)
      i := (end < 0 ? n : end)
    } else if from(i.contents, "/*") {
      let depth = ref(1)
      i := i.contents + 2
      while i.contents < n && depth.contents > 0 {
        if from(i.contents, "/*") {
          depth := depth.contents + 1
          i := i.contents + 2
        } else if from(i.contents, "*/") {
          depth := depth.contents - 1
          i := i.contents + 2
        } else {
          i := i.contents + 1
        }
      }
    } else {
      switch matchAt(rawString, text, i.contents) {
      | Some(raw) =>
        let hashes =
          raw->RegExp.Result.matches->Array.get(0)->Option.flatMap(group => group)->Option.getOr("")
        let close = `"${hashes}`
        let found =
          text->String.indexOfFrom(close, i.contents + raw->RegExp.Result.fullMatch->String.length)
        let end = found < 0 ? n : found + close->String.length
        tokens->Array.push(text->String.slice(~start=i.contents, ~end))
        i := end
      | None =>
        if c == "\"" || ("bc"->String.includes(c) && from(i.contents + 1, "\"")) {
          let start = i.contents
          i := i.contents + (c == "\"" ? 1 : 2)
          while i.contents < n && at(i.contents) != "\"" {
            i := i.contents + (at(i.contents) == "\\" ? 2 : 1)
          }
          i := i.contents + 1
          tokens->Array.push(text->String.slice(~start, ~end=i.contents))
        } else if c == "'" || (c == "b" && from(i.contents + 1, "'")) {
          let start = i.contents
          i := i.contents + (c == "'" ? 1 : 2)
          if from(i.contents, "\\") || from(i.contents + 1, "'") {
            // A character: an escape, or one character and its closing quote.
            while i.contents < n && at(i.contents) != "'" {
              i := i.contents + (at(i.contents) == "\\" ? 2 : 1)
            }
            i := i.contents + 1
          } else {
            // A lifetime or a label: the quote and the name after it.
            while i.contents < n && word(at(i.contents)) {
              i := i.contents + 1
            }
          }
          tokens->Array.push(text->String.slice(~start, ~end=i.contents))
        } else {
          switch matchAt(rawIdentifier, text, i.contents) {
          | Some(raw) =>
            let whole = raw->RegExp.Result.fullMatch
            tokens->Array.push(whole)
            i := i.contents + whole->String.length
          | None =>
            if word(c) {
              let start = i.contents
              while i.contents < n && word(at(i.contents)) {
                i := i.contents + 1
              }
              tokens->Array.push(text->String.slice(~start, ~end=i.contents))
            } else {
              tokens->Array.push(c)
              i := i.contents + 1
            }
          }
        }
      }
    }
  }
  tokens->withoutOptionalSemicolons->unbraced->withoutOptionalCommas
}

/** `text` split into lines as Python's `splitlines` does for these files: no empty last line. */
let lines = (text: string) => {
  let split = text->String.splitByRegExp(lineBreak)->Array.map(line => line->Option.getOr(""))
  if split->Array.at(-1) == Some("") {
    split->Array.pop->ignore
  }
  split
}

/**
 * A Dockerfile's lines without its comments and blank lines, as Docker's own parser drops them; a
 * parser directive is kept, and so is every line of a heredoc, which Docker reads as written.
 */
let dockerfileLines = (text: string): array<string> => {
  let kept = []
  let until = ref(None)
  let dashed = ref(false)
  text
  ->lines
  ->Array.forEach(line =>
    switch until.contents {
    | Some(word) =>
      kept->Array.push(line)
      if (dashed.contents ? line->String.replaceRegExp(leadingTabs, "") : line) == word {
        until := None
      }
    | None =>
      let stripped = line->String.trim
      if (
        stripped != "" && !(stripped->String.startsWith("#") && !(directive->RegExp.test(stripped)))
      ) {
        kept->Array.push(line->String.trimEnd)
        switch heredoc->RegExp.exec(line) {
        | Some(opened) =>
          let groups = opened->RegExp.Result.matches
          dashed := groups->Array.get(0) == Some(Some("-"))
          until := groups->Array.get(1)->Option.flatMap(group => group)
        | None => ()
        }
      }
    }
  )
  kept
}

/**
 * A script's or an ignore file's lines without the blank ones and those that are only a comment;
 * a first line that is a shebang is kept.
 */
let shellLines = (text: string): array<string> => {
  let all = lines(text)
  let head =
    all[0]->Option.mapOr(false, first => first->String.startsWith("#!"))
      ? [all->Array.getUnsafe(0)]
      : []
  let rest = all->Array.slice(~start=head->Array.length)->Array.map(String.trimEnd)
  Array.concat(
    head,
    rest->Array.filter(line =>
      line->String.trim != "" && !(line->String.trim->String.startsWith("#"))
    ),
  )
}

/** A TOML file's value, or its text where it does not parse. */
let tomlValue = (text: string): JSON.t =>
  try Toml.parse(text) catch {
  | _ => JSON.String(text)
  }

type normalized =
  | Tokens(array<string>)
  | Value(JSON.t)

/** How `path` is read for a build, by its kind; None for its bytes. */
let normalizer = (path: string): option<string => normalized> => {
  let name = path->String.slice(~start=path->String.lastIndexOf("/") + 1)
  if name->String.endsWith(".rs") {
    Some(text => Tokens(rustTokens(text)))
  } else if name == "Dockerfile" || name->String.endsWith(".Dockerfile") {
    Some(text => Tokens(dockerfileLines(text)))
  } else if name == "service.toml" || name == "Cargo.toml" {
    Some(text => Value(tomlValue(text)))
  } else if name == ".dockerignore" || path == ".mise/tasks/image" {
    Some(text => Tokens(shellLines(text)))
  } else {
    None
  }
}

/** Whether `path` is read as more than its bytes, and so is worth reading at all. */
let normalized = (path: string): bool => normalizer(path)->Option.isSome

/** Whether `before` and `after`, `path` at two revisions or None where absent, build the same. */
let same = (path: string, before: option<string>, after: option<string>): bool =>
  switch (before, after) {
  | (Some(before), Some(after)) if before != after =>
    switch normalizer(path) {
    | Some(normalize) =>
      switch (normalize(before), normalize(after)) {
      | (Tokens(a), Tokens(b)) => a == b
      | (Value(a), Value(b)) => Node.isDeepStrictEqual(a, b)
      | _ => false
      }
    | None => false
    }
  | _ => before == after
  }
