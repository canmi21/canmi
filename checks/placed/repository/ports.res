/** A dev server's strict port and a test's free one, docs/toolchain/runtime.md and docs/code.md. */
let vite = /(^|\/)vite\.config\.[cm]?[jt]s$/
let strict = /\bstrictPort\s*:\s*true\b/
let named = /(_test|\.test|\.spec)\.[a-z]+$/
let directory = /(^|\/)tests?\//
let literal = /\b(?:listen|bind)\(\s*(?:"[^"]*:)?([1-9][0-9]*)\b/

/** Whether a file is a test, a Rust one by the attribute its text carries. */
let testing = (path, text) =>
  named->RegExp.test(path) ||
  directory->RegExp.test(path) ||
  (path->String.endsWith(".rs") &&
    ["#[cfg(test)]", "#[test]", "::test]"]->Array.some(mark => text->String.includes(mark)))

/** A vite config that does not fail when its port is taken. */
let dev = (path, text) =>
  vite->RegExp.test(path) && !(strict->RegExp.test(text))
    ? Some(`${path}: a vite config without strictPort: true falls back to another port`)
    : None

/** Each line of a test that listens on a literal port. */
let listens = (path, text): array<string> =>
  testing(path, text)
    ? text
      ->String.split("\n")
      ->Array.mapWithIndex((line, index) => {
        let code = line->String.trim
        code->String.startsWith("//") ||
        code->String.startsWith("*") ||
        !(literal->RegExp.test(line))
          ? None
          : Some(`${path}:${Int.toString(index + 1)}: a test binds a literal port, not port 0`)
      })
      ->Array.filterMap(found => found)
    : []

let readable = (~paths: array<string>) => paths->Array.filter(path => !Pinned.vendored(path))

/** Each vite config of the tracked `paths` that does not fail on a taken port. */
let servers = (~root, ~paths: array<string>): array<string> =>
  readable(~paths)->Array.filterMap(path =>
    vite->RegExp.test(path) ? dev(path, Node.readFileSync(Node.join([root, path]))) : None
  )

/** Each listen on a literal port in the tests among the tracked `paths`. */
let tests = (~root, ~paths: array<string>): array<string> =>
  readable(~paths)
  ->Array.filter(path => !(path->String.endsWith(".lock")) && Node.extname(path) != "")
  ->Array.flatMap(path => listens(path, Node.readFileSync(Node.join([root, path]))))
