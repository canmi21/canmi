open Testing

describe("a secrets file", () =>
  test("is safe only as sops writes it, every value encrypted", () => {
    expect(Secrets.unencrypted(`{"sops": {}, "A": "ENC[x]"}`))->toBeUndefined
    expect(Secrets.unencrypted(`{"A": "plain"}`))->toEqual(Some("no sops block: this is plaintext"))
    expect(Secrets.unencrypted(`{"sops": {}, "B": "", "A": "plain"}`))->toEqual(
      Some("values are not encrypted: A, B"),
    )
    expect(Secrets.unencrypted("not json")->Option.getOr(""))->toMatch(/^not readable as JSON/)
  })
)

describe("a comment", () => {
  test("is measured with tabs at two, less its links, in characters", () => {
    expect(Comments.columns("\t// a"))->toBe(6)
    expect(Comments.columns("// see https://example.com/a/very/long/path."))->toBe(8)
    expect(Comments.unlinked("// `https://kept` https://gone"))->toBe("// `https://kept` ")
    expect(Comments.columns("// 渲染"))->toBe(5)
  })

  test("says something when it carries text, a link alone saying nothing", () => {
    expect(Comments.prose("// words"))->toBe(true)
    expect(Comments.prose(" * "))->toBe(false)
    expect(Comments.prose("// https://example.com"))->toBe(false)
    expect(Comments.prose("// 中文 https://example.com"))->toBe(true)
  })

  test("block opening a file is told from one after code, a directive leading neither", () => {
    let lines = [
      "#!/usr/bin/env node",
      "//MISE description=\"x\"",
      "// one",
      "// two",
      "code();",
      "/**",
      " * three",
      " */",
    ]
    expect(Comments.blocks(lines))->toEqual([(3, 2, 6, true), (6, 1, 8, false)])
    expect(Comments.blocks(["// @generated", "// x"]))->toEqual([])
  })
})

describe("a Python file's docstrings", () => {
  let dir = ref("")
  beforeEach(() => dir := mkdtempSync(Node.join([tmpdir(), "comments-"])))
  afterEach(() => Node.rmSync(dir.contents, {recursive: true, force: true}))

  test("are found by Python's parser: the module's opens the file, a function's does not", () => {
    let path = Node.join([dir.contents, "a.py"])
    let text = "\"\"\"The module,\nsaid twice.\"\"\"\n\n\ndef f():\n\t\"\"\"A function.\"\"\"\n\treturn 1\n"
    Node.writeFileSync(path, text)
    let spans = Comments.docstringSpans([path])->Map.get(path)->Option.getOr([])
    expect(spans->Array.toSorted(((a, _, _), (b, _, _)) => Int.toFloat(a - b)))->toEqual([
      (1, 2, true),
      (6, 6, false),
    ])
    expect(Comments.blocks(text->String.split("\n"), ~spans))->toEqual([
      (1, 2, 14, true),
      (6, 1, 19, false),
    ])
  })
})
