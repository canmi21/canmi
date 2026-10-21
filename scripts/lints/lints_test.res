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

  test("is plain with two lines of prose, no colon and no dash, a token or a path aside", () => {
    expect(Comments.marks(["// one line", "// and a second"]))->toEqual([])
    expect(Comments.marks(["// a", "// b", "// c"]))->toEqual(["3 body lines, aiming at 2"])
    expect(Comments.marks(["// says this: that"]))->toEqual(["a colon"])
    expect(Comments.marks(["// one -- two", "// three \u2014 four"]))->toEqual(["a dash"])
    expect(
      Comments.marks(["// `a: b` and std::fs at 10:30, a well-made https://x.io/a:b"]),
    )->toEqual([])
    expect(
      Comments.marks(["// SAFETY: the pointer outlives the call", "// - a list item"]),
    )->toEqual([])
    expect(Comments.marks(["// names it -R or --repository, a well-made x-y"]))->toEqual([])
    expect(Comments.marks(["// any of -2^64 to 2^64 - 1"]))->toEqual([])
    expect(Comments.marks(["// one - two"]))->toEqual(["a dash"])
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
  beforeEach(() => dir := Node.mkdtempSync(Node.join([Node.tmpdir(), "comments-"])))
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
