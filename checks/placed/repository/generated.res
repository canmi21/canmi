/** Generated code opens with its tag and is marked in .gitattributes, docs/repos.md. */
let marking = /^(\S+)\s+(?:linguist-generated(?:=true)?)(?:\s|$)/
let code = [".rs", ".ts", ".js", ".mjs", ".res", ".css", ".py", ".svelte", ".tsx"]
let special = RegExp.fromString("[.+^${}()|\\[\\]\\\\]", ~flags="g")

/** A .gitattributes glob as a pattern over a path from the root. */
let glob = (pattern: string) => {
  let anchored =
    pattern->String.startsWith("/") ||
      pattern->String.slice(~start=0, ~end=-1)->String.includes("/")
  let body = pattern->String.replaceRegExp(/^\//, "")
  let directory = body->String.endsWith("/")
  let body = directory ? body->String.slice(~start=0, ~end=-1) : body
  let source =
    body
    ->String.replaceRegExp(special, "\\$&")
    ->String.replaceAll("**/", "\u0000")
    ->String.replaceAll("**", "\u0001")
    ->String.replaceAll("*", "[^/]*")
    ->String.replaceAll("?", "[^/]")
    ->String.replaceAll("\u0000", "(?:.*/)?")
    ->String.replaceAll("\u0001", ".*")
  RegExp.fromString(`^${anchored ? "" : "(?:.*/)?"}${source}${directory ? "/.*" : "$"}`)
}

/** The globs a .gitattributes marks linguist-generated. */
let marked = (text): array<RegExp.t> =>
  text
  ->String.split("\n")
  ->Array.filterMap(line =>
    switch marking->RegExp.exec(line->String.trim)->Option.map(RegExp.Result.matches) {
    | Some([Some(pattern)]) => Some(glob(pattern))
    | _ => None
    }
  )

/** Whether a file opens with @generated within its first five lines. */
let opens = text =>
  text
  ->String.split("\n")
  ->Array.slice(~start=0, ~end=5)
  ->Array.some(String.includes(_, "@generated"))

/** What a code file breaks, given whether it is marked and whether it opens with the tag. */
let problem = (path, ~marked, ~opens) =>
  switch (marked, opens) {
  | (true, false) => Some(`${path}: is marked linguist-generated and does not open with @generated`)
  | (false, true) => Some(`${path}: opens with @generated and is not marked linguist-generated`)
  | _ => None
  }

let main = (~root, ~paths: array<string>): array<string> => {
  let globs =
    paths->Array.includes(".gitattributes")
      ? marked(Node.readFileSync(Node.join([root, ".gitattributes"])))
      : []
  paths
  ->Array.filter(path => code->Array.includes(Node.extname(path)) && !Pinned.vendored(path))
  ->Array.filterMap(path =>
    problem(
      path,
      ~marked=globs->Array.some(glob => glob->RegExp.test(path)),
      ~opens=opens(Node.readFileSync(Node.join([root, path]))),
    )
  )
}
