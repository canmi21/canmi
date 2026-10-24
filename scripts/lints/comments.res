/**
 * Holds every comment block in a repository to `Code`'s limits, docs/code.md, a body line being
 * one that carries text. Paths given are measured instead of the tree.
 */
let width = Code.columns
let bodyLimit = Code.blockLines
let openingLimit = Code.openingLines
/**
 * A fenced block in a document illustrates code rather than being it, so prose files are skipped.
 */
let skipped = [".md"]
/** Tried in order, `///` before `//`; `#` opens a comment only before a space or the line's end. */
let openers = ["///", "//!", "//", "/**", "/*", "*/", "<!--", "\"\"\"", "'''", "#"]
let closers = ["*/", "-->", "\"\"\"", "'''"]
/** Directives read by a tool, a shebang and mise's task header, which are not prose. */
let directives = ["#!", "#MISE", "#USAGE", "//MISE"]
let preamble = ["set -"]
/** A link, as docs/code.md's "A link is not length" means it, stopping before punctuation. */
let link = /https?:\/\/(?:[^\s`'"]*[^\s`'".,;:!?)\]}])?/g
/** A letter or a digit, in any script. What a link leaves behind is punctuation. */
let letter = /[\p{L}\p{N}]/u
let leadingStars = /^\*+/
let lineEnding = /\r\n?/g

let startsWithAny = (text, prefixes) =>
  prefixes->Array.some(prefix => text->String.startsWith(prefix))

/** The line with every link taken off it; one inside a backtick span is a token, and stays. */
let unlinked = (line: string): string =>
  line->String.replaceRegExpBy0Unsafe(link, (~match, ~offset, ~input as _) =>
    mod(line->String.slice(~start=0, ~end=offset)->String.split("`")->Array.length - 1, 2) == 1
      ? match
      : ""
  )

/** `line` with its tabs expanded to the next stop at two, as Python's `expandtabs(2)` does. */
let expanded = (line: string): array<string> => {
  let out = []
  line
  ->Node.codePoints
  ->Array.forEach(character =>
    switch character {
    | "\t" =>
      for _ in 1 to 2 - mod(out->Array.length, 2) {
        out->Array.push(" ")
      }
    | "\n" | "\r" => out->Array.splice(~start=0, ~remove=out->Array.length, ~insert=[])
    | other => out->Array.push(other)
    }
  )
  out
}

/** The width oxfmt and rustfmt would count, which is tabs at two, less any link. */
let columns = (line: string): int => line->unlinked->expanded->Array.length

/** What one comment line says, with its markers taken off. */
let textOf = (line: string): string => {
  let stripped = ref(line->String.trim)
  switch openers->Array.find(one => stripped.contents->String.startsWith(one)) {
  | Some(opener) => stripped := stripped.contents->String.slice(~start=opener->String.length)
  | None => ()
  }
  closers->Array.forEach(closer =>
    if stripped.contents->String.endsWith(closer) {
      stripped :=
        stripped.contents->String.slice(
          ~start=0,
          ~end=stripped.contents->String.length - closer->String.length,
        )
    }
  )
  stripped.contents->String.replaceRegExp(leadingStars, "")->String.trim
}

/** Whether a comment line says something; only one a link came off is judged by what is left. */
let prose = (line: string): bool => {
  let bare = unlinked(line)
  bare == line ? textOf(line) != "" : letter->RegExp.test(textOf(bare))
}

/** Whether a stripped line opens or continues a `#` comment rather than naming something. */
let hashed = bare =>
  (bare == "#" || bare->String.startsWith("# ") || bare->String.startsWith("#\t")) &&
    !startsWithAny(bare, directives)

/** Whether a tool wrote this file, `@generated` in its first five lines, and so nobody's to fix. */
let generated = lines =>
  lines->Array.slice(~start=0, ~end=5)->Array.some(line => line->String.includes("@generated"))

/** A block as its first line, its body lines, its widest column and whether it opens the file. */
type block = (int, int, int, bool)

/** A docstring's span, `(first, last, opensTheModule)`, from Python's own parser. */
type span = (int, int, bool)

let docstrings = `
import ast, json, sys
spans = {}
for path, text in json.load(sys.stdin):
	try:
		tree = ast.parse(text)
	except (SyntaxError, ValueError):
		continue
	found = []
	for node in ast.walk(tree):
		if not isinstance(node, (ast.Module, ast.AsyncFunctionDef, ast.FunctionDef, ast.ClassDef)):
			continue
		first = node.body[0] if node.body else None
		if not isinstance(first, ast.Expr) or not isinstance(first.value, ast.Constant):
			continue
		if not isinstance(first.value.value, str) or first.end_lineno is None:
			continue
		found.append([first.lineno, first.end_lineno, isinstance(node, ast.Module)])
	spans[path] = found
print(json.dumps(spans))
`

/** Each Python file's docstring spans by its path, asked of python3 once for every file's text. */
let docstringSpans = (texts: array<(string, string)>): Map.t<string, array<span>> =>
  if texts->Array.length == 0 {
    Map.make()
  } else {
    let answer = Node.execFileSync(
      "python3",
      ["-c", docstrings],
      {input: JSON.stringifyAny(texts)->Option.getOr("[]"), encoding: "utf8", maxBuffer: 268435456},
    )
    switch JSON.parseOrThrow(answer) {
    | Object(found) =>
      found
      ->Dict.toArray
      ->Array.map(((path, spans)) => (
        path,
        switch spans {
        | Array(spans) =>
          spans->Array.filterMap(span =>
            switch span {
            | Array([Number(first), Number(last), Boolean(module_)]) =>
              Some((first->Float.toInt, last->Float.toInt, module_))
            | _ => None
            }
          )
        | _ => []
        },
      ))
      ->Map.fromArray
    | _ => Map.make()
    }
  }

/** A file's lines from its bytes, or None where they are not UTF-8, as a binary's are not. */
let decoded = (bytes: Node.bytes): option<array<string>> =>
  try {
    // Newlines read as Python's text mode reads them, a byte-order mark kept as a character.
    let text = Node.textDecoder("utf-8", {fatal: true, ignoreBOM: true})->Node.decode(bytes)
    Some(text->String.replaceRegExp(lineEnding, "\n")->String.split("\n"))
  } catch {
  | _ => None
  }

/** A file's lines, or None where it cannot be read or decoded. */
let linesOf = (path: string): option<array<string>> =>
  Net.readBytesOf(path)->Option.flatMap(decoded)

/** Whether a file is Python, by its suffix or its first line. */
let isPython = (path, lines) =>
  path->String.endsWith(".py") || lines[0]->Option.getOr("")->String.includes("python")

/** The Python files among those read, each by its path with its text. */
let pythonTexts = (read: array<(string, option<array<string>>)>) =>
  read->Array.filterMap(((path, lines)) =>
    switch lines {
    | Some(lines) if isPython(path, lines) => Some((path, lines->Array.join("\n")))
    | _ => None
    }
  )

let widest = body => body->Array.reduce(0, (most, line) => Math.Int.max(most, columns(line)))
let spoken = body => body->Array.filter(prose)->Array.length

/** Each block in `lines`, by its first line, its lines and whether it opens the file. */
let found = (lines: array<string>, ~spans: array<span>=[]): array<(int, array<string>, bool)> =>
  if generated(lines) {
    []
  } else {
    let found = []
    let claimed = Set.make()
    spans->Array.forEach(((first, last, module_)) => {
      for number in first to last {
        claimed->Set.add(number)
      }
      found->Array.push((first, lines->Array.slice(~start=first - 1, ~end=last), module_))
    })
    let codeSeen = ref(false)
    let index = ref(0)
    let at = () => lines->Array.getUnsafe(index.contents)
    while index.contents < lines->Array.length {
      let start = index.contents
      let bare = at()->String.trim
      if startsWithAny(bare, directives) || (!codeSeen.contents && startsWithAny(bare, preamble)) {
        index := index.contents + 1
      } else if claimed->Set.has(index.contents + 1) {
        codeSeen := true
        index := index.contents + 1
      } else if bare->String.startsWith("/*") || bare->String.startsWith("<!--") {
        let closer = bare->String.startsWith("/*") ? "*/" : "-->"
        while index.contents < lines->Array.length && !(at()->String.includes(closer)) {
          index := index.contents + 1
        }
        index := Math.Int.min(index.contents, lines->Array.length - 1)
        let body = lines->Array.slice(~start, ~end=index.contents + 1)
        index := index.contents + 1
        found->Array.push((start + 1, body, !codeSeen.contents))
      } else if bare->String.startsWith("//") {
        while index.contents < lines->Array.length && at()->String.trim->String.startsWith("//") {
          index := index.contents + 1
        }
        found->Array.push((
          start + 1,
          lines->Array.slice(~start, ~end=index.contents),
          !codeSeen.contents,
        ))
      } else if hashed(bare) {
        while index.contents < lines->Array.length && hashed(at()->String.trim) {
          index := index.contents + 1
        }
        found->Array.push((
          start + 1,
          lines->Array.slice(~start, ~end=index.contents),
          !codeSeen.contents,
        ))
      } else {
        codeSeen := codeSeen.contents || bare != ""
        index := index.contents + 1
      }
    }
    found
  }

/** Every comment block in a file's `lines`, Python's docstrings given as `spans`. */
let blocks = (lines: array<string>, ~spans: array<span>=[]): array<block> =>
  found(lines, ~spans)
  ->Array.map(((first, body, opening)) => (first, spoken(body), widest(body), opening))
  ->Array.toSorted(((a1, a2, a3, a4), (b1, b2, b3, b4)) =>
    Int.toFloat(
      a1 != b1 ? a1 - b1 : a2 != b2 ? a2 - b2 : a3 != b3 ? a3 - b3 : (a4 ? 1 : 0) - (b4 ? 1 : 0),
    )
  )

/** A code span, which is a token rather than prose. */
let span = /`[^`]*`/g
/** A label a tool asks for, such as clippy's `SAFETY:`, and a list's leading hyphen. */
let label = /^(?:[A-Z]+:|- )/
/** A colon in prose, not a path's `::` nor a time's or a ratio's between digits. */
let colon = /(?<![:\d]):(?![:\d])|(?<=\D):(?=\d)|(?<=\d):(?=\D)/
/** A dash, two hyphens alone, one between words, or an em or en dash, never a flag or a minus. */
let dash = /(?:^|\s)--(?:\s|$)|(?<=[A-Za-z,])\s-\s(?=[A-Za-z])|\u2014|\u2013/

/** What a block's prose holds that docs/code.md asks a comment to do without. */
let marks = (body: array<string>): array<string> => {
  let text =
    body
    ->Array.map(line => line->unlinked->textOf->String.replaceRegExp(label, ""))
    ->Array.join(" ")
    ->String.replaceRegExp(span, "")
  let found = []
  if spoken(body) > Code.aimLines {
    found->Array.push(
      `${Int.toString(spoken(body))} body lines, aiming at ${Int.toString(Code.aimLines)}`,
    )
  }
  if colon->RegExp.test(text) {
    found->Array.push("a colon")
  }
  if dash->RegExp.test(text) {
    found->Array.push("a dash")
  }
  found
}

/** The files to measure, everything version control lists with untracked but unignored ones. */
let files = (root, given) =>
  given->Array.length > 0
    ? given
    : Node.execFileSync(
        "git",
        ["-C", root, "ls-files", "--cached", "--others", "--exclude-standard", "-z"],
        {encoding: "utf8", maxBuffer: 268435456},
      )
      ->String.split("\x00")
      ->Array.filter(name =>
        name != "" && !(skipped->Array.some(suffix => name->String.endsWith(suffix)))
      )
      ->Array.map(name => Node.join([root, name]))

/** Every block longer than `Code.aimLines` or carrying a colon or a dash, one warning each. */
let plain = (~root=Node.cwd(), ~given=[]): array<string> => {
  let read = files(root, given)->Array.map(path => (path, linesOf(path)))
  let spans = docstringSpans(pythonTexts(read))
  read->Array.flatMap(((path, lines)) =>
    switch lines {
    | Some(lines) =>
      let name = Node.isAbsolute(path) ? Node.relative(root, path) : path
      found(lines, ~spans=spans->Map.get(path)->Option.getOr([]))->Array.filterMap(((
        first,
        body,
        _,
      )) =>
        switch marks(body) {
        | [] => None
        | why => Some(`${name}:${Int.toString(first)}  ${why->Array.join(", ")}`)
        }
      )
    | None => []
    }
  )
}

/** Each block past its limits in the files `read`, by where and how much, failing at a push. */
let judged = (~root, read: array<(string, option<array<string>>)>, ~at=?, ~pushing) => {
  let spans = docstringSpans(pythonTexts(read))
  let over = []
  let counted = ref(0)
  read->Array.forEach(((path, lines)) =>
    switch lines {
    | None => ()
    | Some(lines) =>
      let inside = !Node.isAbsolute(path) || !(Node.relative(root, path)->String.startsWith(".."))
      let name = inside && Node.isAbsolute(path) ? Node.relative(root, path) : path
      found(lines, ~spans=spans->Map.get(path)->Option.getOr([]))
      ->Array.toSorted(((a, _, _), (b, _, _)) => Int.toFloat(a - b))
      ->Array.forEach(((line, body, opening)) => {
        counted := counted.contents + 1
        let limit = opening ? openingLimit : bodyLimit
        let numbered = body->Array.mapWithIndex((text, at) => (line + at, text))
        let wide = numbered->Array.filter(((_, text)) => columns(text) > width)
        let spokenLines = numbered->Array.filter(((_, text)) => prose(text))
        let why = []
        if wide != [] {
          why->Array.push(`${Int.toString(widest(body))} columns over ${Int.toString(width)}`)
        }
        if spokenLines->Array.length > limit {
          why->Array.push(
            `${Int.toString(spokenLines->Array.length)} body lines over ${Int.toString(limit)}`,
          )
        }
        if why->Array.length > 0 {
          let onset = inside
            ? Onset.block(
                ~root,
                Node.relative(root, Node.resolve([path])),
                ~spoken=spokenLines->Array.map(((number, _)) => number),
                ~limit,
                ~wide=wide->Array.map(((number, _)) => number),
                ~at?,
              )
            : None
          over->Array.push(
            `${name}:${Int.toString(line)}  ${why->Array.join(", ")}${Onset.said(onset)}`,
          )
        }
      })
    }
  )
  let failing = Form_layer.fails(~pushing)
  if over->Array.length > 0 {
    let say = failing ? Console.error : Console.log
    say(
      failing
        ? "Comment blocks over a limit:\n"
        : "Comment blocks over a limit, warned until a push:\n",
    )
    over->Array.forEach(problem => say(`  ${problem}`))
    say(
      "\nCut to the line that carries the point. A fact a second file would need is a rule and " ++
      "belongs in the rules; one only this file needs stays here, in fewer words. See the " ++ "workspace's docs/code.md, \"How long, and where the rest of it goes\".",
    )
  } else {
    Console.log(
      `comments OK: ${Int.toString(counted.contents)} blocks inside ${Int.toString(
          bodyLimit,
        )}/${Int.toString(openingLimit)} body lines and ${Int.toString(width)} columns`,
    )
  }
  failing && over->Array.length > 0 ? 1 : 0
}

/** The gate over the working copy, or over the paths given. */
let main = (~root=Node.cwd(), ~given=Node.args(), ~pushing=false) =>
  judged(~root, files(root, given)->Array.map(path => (path, linesOf(path))), ~pushing)

/** The gate over a tree, its files read as they are there. */
let measured = (tree: Lines.tree, ~pushing) =>
  judged(
    ~root=tree.root,
    tree.paths
    ->Array.filter(name => !(skipped->Array.some(suffix => name->String.endsWith(suffix))))
    ->Array.map(name => (Node.join([tree.root, name]), tree.bytes(name)->Option.flatMap(decoded))),
    ~at=?tree.at,
    ~pushing,
  )

if Node.isMain {
  Node.exit(main())
}
