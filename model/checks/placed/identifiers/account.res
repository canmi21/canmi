/** The author's account name kept out of code's structure, `account-name` in naming.res. */
let name = "canmi21"
let kinds = [".res", ".ts", ".tsx", ".js", ".mjs", ".rs", ".svelte"]
let literal = mark => `${mark}(?:[^${mark}\\\\\\n]|\\\\.)*${mark}`
let strings = RegExp.fromString(
  ["\\x22", "\\x27", "\\x60"]->Array.map(literal)->Array.join("|"),
  ~flags="g",
)
let quoted = "[\\x22\\x27\\x60]canmi21[\\x22\\x27\\x60]"

/** A string equal to the name that a comparison, a match arm or a string test decides by. */
let deciding = RegExp.fromString(
  [
    `[!=]==?\\s*${quoted}`,
    `${quoted}\\s*(?:[!=]==?|=>)`,
    `\\bcase\\s+${quoted}`,
    `\\.(?:includes|startsWith|endsWith|equals)\\(\\s*${quoted}`,
  ]->Array.join("|"),
  ~flags="i",
)

/** Whether `path` is source the check reads, compiled output and a vendored tree never. */
let read = path =>
  kinds->Array.includes(Node.extname(path)) &&
  !(path->String.endsWith(".res.mjs")) &&
  !Layout.vendored(path)

/** Each line of a source that names the account in an identifier or decides by it. */
let problems = (text, ~file): array<string> => {
  let code = Quoting.blanked(text, ~quotes=Sources.quotesOf(file))
  let named = RegExp.fromString(name, ~flags="i")
  let spaced =
    code->String.replaceRegExpBy0Unsafe(strings, (~match, ~offset as _, ~input as _) =>
      match->String.replaceRegExp(/[^\n]/g, " ")
    )
  let say = (found, why) => `${file}:${Int.toString(found)}: ${why}`
  let lines = (source, pattern) =>
    source
    ->String.split("\n")
    ->Array.mapWithIndex((line, index) => pattern->RegExp.test(line) ? Some(index + 1) : None)
    ->Array.filterMap(found => found)
  Array.concat(
    lines(spaced, named)->Array.map(found => say(found, `${name} is in an identifier`)),
    lines(code, deciding)->Array.map(found => say(found, `code decides by ${name}`)),
  )
}

/** Each identifier and decision on the account name among the tracked `paths` of `root`. */
let main = (~root, ~paths: array<string>): array<string> =>
  paths
  ->Array.filter(read)
  ->Array.flatMap(path => problems(References.read(Node.join([root, path])), ~file=path))
