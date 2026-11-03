/** Identifier words held by naming's identifiers-whole in model/rules/naming.res. */
let words = identifier =>
  identifier
  ->String.replaceRegExp(/([A-Z]+)([A-Z][a-z])/g, "$1_$2")
  ->String.replaceRegExp(/([a-z0-9])([A-Z])/g, "$1_$2")
  ->String.toLowerCase
  ->String.split("_")

/** Comments and literals become spaces with their original newlines and offsets kept. */
let code = (text, ~file) => {
  let rust = Node.extname(file) == ".rs"
  let python = Node.extname(file) == ".py"
  let length = String.length(text)
  let at = ref(0)
  let lineComment = ref(false)
  let blockDepth = ref(0)
  let attributeDepth = ref(0)
  let quote = ref("")
  let escaped = ref(false)
  let output = []
  let starts = spelling => text->String.slice(~start=at.contents)->String.startsWith(spelling)
  let take = (count, ~blank) => {
    for offset in 0 to count - 1 {
      let character = text->String.slice(~start=at.contents + offset, ~end=at.contents + offset + 1)
      output->Array.push(blank && character != "\n" ? " " : character)
    }
    at := at.contents + count
  }
  while at.contents < length {
    let character = text->String.slice(~start=at.contents, ~end=at.contents + 1)
    if lineComment.contents {
      lineComment := character != "\n"
      take(1, ~blank=true)
    } else if blockDepth.contents > 0 {
      if starts("/*") {
        blockDepth := blockDepth.contents + 1
        take(2, ~blank=true)
      } else if starts("*/") {
        blockDepth := blockDepth.contents - 1
        take(2, ~blank=true)
      } else {
        take(1, ~blank=true)
      }
    } else if quote.contents != "" {
      if escaped.contents {
        escaped := false
        take(1, ~blank=true)
      } else if character == "\\" {
        escaped := true
        take(1, ~blank=true)
      } else if starts(quote.contents) {
        let width = String.length(quote.contents)
        quote := ""
        take(width, ~blank=true)
      } else {
        take(1, ~blank=true)
      }
    } else if (!python && starts("//")) || (python && character == "#") {
      lineComment := true
      take(1, ~blank=true)
    } else if !python && starts("/*") {
      blockDepth := 1
      take(2, ~blank=true)
    } else if (
      rust && character == "#" && /^#!?\s*\[/->RegExp.test(text->String.slice(~start=at.contents))
    ) {
      let opening = /^#!?\s*\[/->RegExp.exec(text->String.slice(~start=at.contents))
      let width = opening->Option.mapOr(0, result => result->RegExp.Result.fullMatch->String.length)
      attributeDepth := 1
      take(width, ~blank=true)
    } else if (
      rust &&
      character == "'" &&
      {
        switch /^'[A-Za-z_][A-Za-z0-9_]*/->RegExp.exec(text->String.slice(~start=at.contents)) {
        | None => false
        | Some(result) =>
          let end = at.contents + String.length(RegExp.Result.fullMatch(result))
          text->String.slice(~start=end, ~end=end + 1) != "'"
        }
      }
    ) {
      take(1, ~blank=attributeDepth.contents > 0)
    } else if character == "\"" || character == "'" || character == "`" {
      let tripled = character ++ character ++ character
      quote := (python && starts(tripled) ? tripled : character)
      take(String.length(quote.contents), ~blank=true)
    } else if attributeDepth.contents > 0 {
      if character == "[" {
        attributeDepth := attributeDepth.contents + 1
      } else if character == "]" {
        attributeDepth := attributeDepth.contents - 1
      }
      take(1, ~blank=true)
    } else {
      take(1, ~blank=false)
    }
  }
  output->Array.join("")
}

let problems = (text, ~file) => {
  let source = code(text, ~file)
  References.each(/[A-Za-z_$][A-Za-z0-9_$]*/g, source)->Array.flatMap(found => {
    let parts = words(found.whole)
    let held = Naming.abbreviations->Array.filter(((short, _)) => parts->Array.includes(short))
    let rust = Node.extname(file) == ".rs"
    if (
      held == [] ||
      Naming.abbreviationsExempt->Array.includes(found.whole) ||
      (rust && found.whole == "Err")
    ) {
      []
    } else {
      let before = source->String.slice(~start=0, ~end=found.index)
      let trimmed = before->String.trimEnd
      let after = source->String.slice(~start=found.index + String.length(found.whole))

      // A member, a decorator and a Rust macro are spelled by whoever declares them.
      if (
        trimmed->String.endsWith(".") ||
        trimmed->String.endsWith("::") ||
        trimmed->String.endsWith("@") ||
        (rust && after->String.startsWith("!"))
      ) {
        []
      } else {
        let line = before->String.split("\n")->Array.length
        held->Array.map(((short, whole)) =>
          `${file}:${Int.toString(line)}: ${found.whole} holds ${short}, written ${whole}`
        )
      }
    }
  })
}

let sources = [".rs", ".res", ".resi", ".ts", ".tsx", ".js", ".mjs", ".svelte", ".py", ".go"]

let found = (~root) =>
  References.tracked(root)->Array.flatMap(path => {
    let relative = Node.relative(root, path)
    if (
      Layout.vendored(relative) ||
      path->String.endsWith(".res.mjs") ||
      !(sources->Array.includes(Node.extname(path)))
    ) {
      []
    } else {
      let text = try Some(Node.readFileSync(path)) catch {
      | _ => None
      }
      text->Option.mapOr([], text => problems(text, ~file=relative))
    }
  })

let warned = (~root): array<string> => {
  let findings = found(~root)
  if findings->Array.length > 0 {
    Console.log(
      `  warning: ${Int.toString(
          Array.length(findings),
        )} abbreviated identifiers, by naming's identifiers-whole`,
    )
    findings->Array.slice(~start=0, ~end=5)->Array.forEach(Console.log)
  }
  []
}

if Node.isMain {
  found(~root=Node.args()->Array.get(0)->Option.getOr(Node.cwd()))->Array.forEach(Console.log)
}
