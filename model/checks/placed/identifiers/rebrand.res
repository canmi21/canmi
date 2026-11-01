/** Twitter named whole, never by the bare letter, `rebrand-kept` in model/rules/naming.res. */
let host = /(?<![\w.@-])(?:[a-z0-9-]+\.)*x\.com(?![\w-])/gi
let declared = /\b(?:module|class|struct|enum|trait|interface)\s+X\b/g
let stem = /^x(?:[-_.]|$)/i

/** Whether a path names a file or a directory by the bare letter. */
let named = path =>
  path
  ->String.split("/")
  ->Array.some(part => stem->RegExp.test(part))

/** Each address, module or type of a text that names Twitter by the bare letter. */
let problems = (text, ~file): array<string> =>
  Array.concat(
    named(file) ? [`${file}: a path names Twitter by the bare letter; write twitter`] : [],
    text
    ->String.split("\n")
    ->Array.mapWithIndex((line, index) =>
      [host, declared]->Array.flatMap(pattern =>
        References.each(pattern, line)->Array.map(
          found =>
            `${file}:${Int.toString(index + 1)}: ${found.whole} names Twitter by the bare letter`,
        )
      )
    )
    ->Array.flat,
  )

/** The text kinds a bare Twitter address or type is looked for in. */
let kinds = Array.concat(Account.kinds, [".json", ".toml", ".yaml", ".yml"])

/** Each path and line naming Twitter by the bare letter among the tracked `paths` of `root`. */
let main = (~root, ~paths: array<string>): array<string> =>
  paths
  ->Array.filter(path => !Layout.vendored(path))
  ->Array.flatMap(path =>
    problems(
      kinds->Array.includes(Node.extname(path)) && !(path->String.endsWith(".res.mjs"))
        ? References.read(Node.join([root, path]))
        : "",
      ~file=path,
    )
  )
