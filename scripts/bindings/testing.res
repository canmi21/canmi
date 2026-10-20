/** As much of vitest as the scripts' tests call. */
@module("vitest") external describe: (string, unit => unit) => unit = "describe"
@module("vitest") external test: (string, unit => unit) => unit = "test"
@module("vitest") external beforeEach: (unit => unit) => unit = "beforeEach"
@module("vitest") external afterEach: (unit => unit) => unit = "afterEach"

type expectation<'a>
@module("vitest") external expect: 'a => expectation<'a> = "expect"
@send external toBe: (expectation<'a>, 'a) => unit = "toBe"
@send external toEqual: (expectation<'a>, 'a) => unit = "toEqual"
@send external toMatch: (expectation<string>, RegExp.t) => unit = "toMatch"
@send external toBeUndefined: expectation<'a> => unit = "toBeUndefined"

@module("vitest") external expectAs: ('a, string) => expectation<'a> = "expect"
@send external toContain: (expectation<'a>, 'b) => unit = "toContain"
@get external negated: expectation<'a> => expectation<'a> = "not"

type recursive = {recursive: bool}
@module("node:fs") external mkdirSync: (string, recursive) => unit = "mkdirSync"

/** Files under `root`, each path to its text. */
let tree = (root, files: array<(string, string)>) =>
  files->Array.forEach(((path, text)) => {
    mkdirSync(Node.dirname(Node.join([root, path])), {recursive: true})
    Node.writeFileSync(Node.join([root, path]), text)
  })

/** A temporary directory made before each test and removed after it. */
let temporaryRoot = prefix => {
  let root = ref("")
  beforeEach(() => root := Node.mkdtempSync(Node.join([Node.tmpdir(), prefix])))
  afterEach(() => Node.rmSync(root.contents, {recursive: true, force: true}))
  root
}
