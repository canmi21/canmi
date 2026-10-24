open Testing

/** jj run in a scratch repository, its answer or nothing. */
let jj = (root, args) => Onset.read(~root, args)->Option.getOr("")

/** Each step's files written, then committed under its name. */
let history = (root, steps: array<(string, array<(string, string)>)>) => {
  Node.env->Dict.set("JJ_USER", "test")
  Node.env->Dict.set("JJ_EMAIL", "test@localhost")
  jj(root, ["git", "init", "--colocate"])->ignore
  steps->Array.forEach(((name, files)) => {
    tree(root, files)
    jj(root, ["commit", "-m", name])->ignore
  })
}

/** The commit `back` steps behind the working copy, by its id. */
let behind = (root, back) =>
  jj(root, ["log", "--no-graph", "-r", "@" ++ String.repeat("-", back), "-T", "commit_id"])

let numbered = count =>
  Array.fromInitializer(~length=count, at => Int.toString(at))->Array.join("\n")

describe("the form layer", () => {
  test("is every rule marked Form, held by the shape, lines and comments parts", () => {
    expect(Form_layer.rules->Array.toSorted(String.compare))->toEqual([
      "comment-short",
      "file-short",
      "form-at-commit",
      "push-form-clear",
      "tree-deep",
      "tree-wide",
    ])
    expect(Form_layer.parts->Array.toSorted(String.compare))->toEqual([
      "comments",
      "lines",
      "shape",
    ])
  })

  test("warns at a commit, and fails under AUDIT or at a push, its other findings failing", () => {
    let wide: Form_layer.finding = {rule: "tree-wide", says: "d/: wide", onset: () => None}
    let rooted: Form_layer.finding = {rule: "root-configuration", says: "a.rs", onset: () => None}
    expect(Check.outcome(Waivable("nowhere", () => [wide])))->toBe(0)
    expect(Check.outcome(Waivable("nowhere", () => [wide]), ~pushing=true))->toBe(1)
    expect(Check.outcome(Waivable("nowhere", () => [rooted])))->toBe(1)
    Node.env->Dict.set("AUDIT", "1")
    expect(Check.outcome(Waivable("nowhere", () => [wide])))->toBe(1)
    Node.env->Dict.delete("AUDIT")
  })
})

describe("since when a form finding has held", () => {
  let root = temporaryRoot("onset-")

  test("is the oldest commit of a file's run past its limit, and the commits since", () => {
    let root = root.contents
    history(
      root,
      [
        ("short", [("a.txt", numbered(2))]),
        ("long", [("a.txt", numbered(5))]),
        ("other", [("b.txt", "b")]),
        ("longer", [("a.txt", numbered(6))]),
      ],
    )
    expect(Onset.file(~root, "a.txt", ~limit=3))->toEqual(Some(Committed(behind(root, 3), 2)))
    expect(Onset.file(~root, "a.txt", ~limit=9))->toEqual(None)
  })

  test("reads a directory's entries from the files under it", () => {
    let root = root.contents
    history(
      root,
      [
        ("one", [("d/a", "a")]),
        ("three", [("d/b", "b"), ("d/c", "c")]),
        ("nested", [("d/x/y", "y")]),
      ],
    )
    expect(Onset.entries("d", ["d/a", "d/x/y", "d/x/z", "e/f"]))->toBe(2)
    expect(Onset.directory(~root, "d", ~holds=files => Onset.entries("d", files) > 2))->toEqual(
      Some(Committed(behind(root, 2), 1)),
    )
  })

  test("is the commit a comment block's line past its limit came in", () => {
    let root = root.contents
    history(
      root,
      [
        ("two", [("f.res", "// a\n// b\nlet x = 1\n")]),
        ("four", [("f.res", "// a\n// b\n// c\n// d\nlet x = 1\n")]),
      ],
    )
    expect(Onset.block(~root, "f.res", ~spoken=[1, 2, 3, 4], ~limit=3, ~wide=[]))->toEqual(
      Some(Committed(behind(root, 1), 0)),
    )
    expect(Onset.block(~root, "f.res", ~spoken=[1, 2, 3, 4], ~limit=1, ~wide=[]))->toEqual(
      Some(Committed(behind(root, 2), 1)),
    )
    tree(root, [("f.res", "// a\n// b\n// c\n// d\n// e\nlet x = 1\n")])
    expect(Onset.block(~root, "f.res", ~spoken=[1, 2, 3, 4, 5], ~limit=4, ~wide=[]))->toEqual(
      Some(Working),
    )
    expect(Onset.said(Some(Committed("0123456789abcdef", 1))))->toBe(
      " (first in 0123456789ab, 1 commit since)",
    )
  })

  test("lets a planted file past the hard limit pass a commit and stops a push", () => {
    let root = root.contents
    history(root, [("long", [("long.txt", numbered(Code.hardLines + 1))])])
    expect(Check.outcome(Formed(pushing => Lines.main(~given=[root], ~pushing))))->toBe(0)
    jj(root, ["bookmark", "set", "main", "-r", "@-"])->ignore
    expect(Check.gate(root, ~bookmarks=["main"]))->toBe(1)
  })

  test("lets a comment block past its limit pass a commit and stops a push", () => {
    let root = root.contents
    let block = Array.fromInitializer(~length=Code.openingLines + 1, _ => "// words")
    history(root, [("block", [("f.res", block->Array.join("\n") ++ "\nlet x = 1\n")])])
    expect(Comments.main(~root, ~given=[]))->toBe(0)
    expect(Comments.main(~root, ~given=[], ~pushing=true))->toBe(1)
  })
})

describe("the gate before a push", () => {
  let root = temporaryRoot("gate-")
  let block =
    Array.fromInitializer(~length=Code.openingLines + 1, _ => "// words")->Array.join("\n")
  let wide = Array.fromInitializer(~length=Layout.widest + 1, at => (`d/${Int.toString(at)}`, "x"))

  test("refuses a commit whose tree breaks the form layer though the working copy is clean", () => {
    let root = root.contents
    history(
      root,
      [
        (
          "debts",
          [
            ("long.txt", numbered(Code.hardLines + 1)),
            ("f.res", block ++ "\nlet x = 1\n"),
            ...wide,
          ],
        ),
      ],
    )
    jj(root, ["bookmark", "set", "main", "-r", "@-"])->ignore
    tree(root, [("long.txt", numbered(2)), ("f.res", "let x = 1\n")])
    wide->Array.forEach(
      ((path, _)) => Node.rmSync(Node.join([root, path]), {recursive: true, force: true}),
    )
    expect(Lines.main(~given=[root], ~pushing=true))->toBe(0)
    expect(Comments.main(~root, ~given=[], ~pushing=true))->toBe(0)
    let commit = jj(root, ["log", "--no-graph", "-r", "main", "-T", "commit_id"])
    Check.formed(root, Lines.committed(root, commit))->Array.forEach(
      ((name, part)) => expectAs(Check.outcome(part, ~pushing=true), name)->toBe(1),
    )
    expect(Check.gate(root, ~bookmarks=["main"]))->toBe(1)
  })

  test("passes a clean commit though the working copy holds a file too long", () => {
    let root = root.contents
    history(root, [("short", [("a.txt", "a")])])
    jj(root, ["bookmark", "set", "main", "-r", "@-"])->ignore
    tree(root, [("long.txt", numbered(Code.hardLines + 1)), ("f.res", block ++ "\nlet x = 1\n")])
    expect(Lines.main(~given=[root], ~pushing=true))->toBe(1)
    expect(Check.gate(root, ~bookmarks=["main"]))->toBe(0)
  })
})
