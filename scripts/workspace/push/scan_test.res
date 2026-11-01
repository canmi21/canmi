open Testing

let identifiers = Scan.listed("machine.example\n\n  192.0.2.1  \n")

let diff =
  [
    "diff --git a/notes.md b/notes.md",
    "--- a/notes.md",
    "+++ b/notes.md",
    "@@ -1,2 +1,3 @@",
    " first",
    "+reach machine.example here",
    " third",
    "diff --git a/new.txt b/new.txt",
    "new file mode 100644",
    "--- /dev/null",
    "+++ b/new.txt",
    "@@ -0,0 +1,2 @@",
    "+submachine.example_x is not it",
    "+at 192.0.2.1",
  ]->Array.join("\n")

let one = (~diff="", ~message="") => [{Scan.id: "aaaaaaaaaaaa", diff, message}]

let lineHit = (file, number, identifier) => {
  Scan.place: Line(file, number),
  identifier,
  commit: Some("aaaaaaaaaaaa"),
}

describe("what a push sends", () => {
  test("the list is read one identifier per line, blank lines passed over", () => {
    expect(identifiers)->toEqual([
      {Scan.identifier: "machine.example", exceptions: [], allowed: None},
      {identifier: "192.0.2.1", exceptions: [], allowed: None},
    ])
  })

  test("a comment is passed over, and a marker puts every entry after it in its group", () => {
    expect(
      Scan.listed(
        "# the fleet\nkestrel\n# allowed in monoflake/cloud\nheron\twren\n# a note\nplover\n",
      ),
    )->toEqual([
      {Scan.identifier: "kestrel", exceptions: [], allowed: None},
      {identifier: "heron", exceptions: ["wren"], allowed: Some("monoflake/cloud")},
      {identifier: "plover", exceptions: [], allowed: Some("monoflake/cloud")},
    ])
    expect(
      Scan.listed("heron\n# allowed in canmi/web\nplover\n# allowed in monoflake/cloud\nwren\n"),
    )->toEqual([
      {Scan.identifier: "heron", exceptions: [], allowed: None},
      {identifier: "plover", exceptions: [], allowed: Some("canmi/web")},
      {identifier: "wren", exceptions: [], allowed: Some("monoflake/cloud")},
    ])
  })

  test("the lines' identifiers are counted once each, the repository's group apart", () => {
    let entries = Scan.listed("kestrel\n# allowed in monoflake/cloud\nheron\tgrey heron\nplover\n")
    let lines = ["kestrel and heron", "heron again", "a grey heron passes", "nothing"]
    expect(Scan.counted(lines, entries, ~repo="monoflake/cloud"))->toEqual((1, 1))
    expect(Scan.counted(lines, entries, ~repo="canmi/web"))->toEqual((0, 2))
    expect(Scan.counted(["a grey heron"], entries, ~repo="monoflake/cloud"))->toEqual((0, 0))
  })

  test("an entry carries its exceptions after it, each after a tab", () => {
    expect(Scan.listed("kestrel\tkestrel[-_]?\\d+\t kestrel\\.example \n"))->toEqual([
      {
        Scan.identifier: "kestrel",
        exceptions: ["kestrel[-_]?\\d+", "kestrel\\.example"],
        allowed: None,
      },
    ])
  })

  test("a list whose exception is no pattern is not read, so the scan never runs short", () => {
    expect(Scan.checked("kestrel\tkestrel(\n"))->toEqual(None)
    expect(Scan.checked("kestrel\n")->Option.isSome)->toBe(true)
  })

  test("a hit inside an exception's match passes, and a bare use beside it is still a hit", () => {
    let entries = Scan.listed("kestrel\tkestrel[-_]?\\d+")
    let lines = (text: string) =>
      Scan.tracked([("a.md", text)], entries)->Array.map(
        ({place}) =>
          switch place {
          | Line(_, number) => number
          | Message => 0
          },
      )
    expect(
      lines("KESTREL-256\nkestrel1 and Kestrel_512\nkestrel-7x\nkestrel KESTREL-256\n"),
    )->toEqual([3, 4])
    expect(lines("see kestrel\n"))->toEqual([1])
  })

  test("a hit in an added line is found and named by its commit, file and line", () => {
    let sent = Scan.sent(one(~diff), identifiers)
    expect(sent)->toEqual([
      lineHit("notes.md", 2, "machine.example"),
      lineHit("new.txt", 2, "192.0.2.1"),
    ])
    expect(Scan.shown("canmi/lib", sent->Array.getUnsafe(0)))->toBe(
      "canmi/lib: aaaaaaaaaaaa notes.md:2 holds machine.example",
    )
  })

  test("a word that merely contains an identifier is not a hit", () => {
    expect(Scan.holds("submachine.example_x", "machine.example"))->toBe(false)
    expect(Scan.holds("machine.examples", "machine.example"))->toBe(false)
    expect(Scan.holds("1192.0.2.1", "192.0.2.1"))->toBe(false)
    expect(Scan.holds("machineXexample", "machine.example"))->toBe(false)
    expect(Scan.holds("(machine.example)", "machine.example"))->toBe(true)
    expect(Scan.holds("xmachine.example machine.example", "machine.example"))->toBe(true)
  })

  test("an identifier is matched in any case", () => {
    expect(Scan.holds("Machine.Example starts it", "machine.example"))->toBe(true)
    expect(Scan.holds("MACHINE.EXAMPLE", "machine.example"))->toBe(true)
    expect(Scan.holds("SubMachine.Example", "machine.example"))->toBe(false)
  })

  test("a removed line or a header is not what is sent", () => {
    let removed =
      "--- a/machine.example\n+++ b/machine.example\n@@ -1 +0,0 @@\n" ++ "-machine.example\n machine.example"
    expect(Scan.sent(one(~diff=removed), identifiers))->toEqual([])
  })

  test("a hit in a commit message is found", () => {
    let sent = Scan.sent(one(~message="docs: name the host\n\nsee 192.0.2.1\n"), identifiers)
    expect(sent)->toEqual([
      {Scan.place: Message, identifier: "192.0.2.1", commit: Some("aaaaaaaaaaaa")},
    ])
    expect(Scan.shown("workspace", sent->Array.getUnsafe(0)))->toBe(
      "workspace: aaaaaaaaaaaa a commit message holds 192.0.2.1",
    )
  })

  test("an identifier one commit adds and a later one removes is still sent", () => {
    let first = "--- a/x\n+++ b/x\n@@ -1 +1,2 @@\n kept\n+reach machine.example"
    let second = "--- a/x\n+++ b/x\n@@ -1,2 +1 @@\n kept\n-reach machine.example"
    let commits = [
      {Scan.id: "111111111111", diff: first, message: "feat: add"},
      {id: "222222222222", diff: second, message: "fix: drop"},
    ]
    expect(Scan.sent(commits, identifiers))->toEqual([
      {Scan.place: Line("x", 2), identifier: "machine.example", commit: Some("111111111111")},
    ])
  })

  test("SKIP naming the scan passes a hit, and only the scan", () => {
    let sent = Scan.sent(one(~diff), identifiers)
    let (passed, refused) = Scan.verdict(sent, ~skip=Some("verify, scan"))
    expect((passed->Array.length, refused))->toEqual((2, []))
    expect(Scan.verdict(sent, ~skip=Some("verify"))->Pair.second->Array.length)->toBe(2)
    expect(Scan.verdict(sent, ~skip=Some("scanned"))->Pair.second->Array.length)->toBe(2)
  })
})

describe("what a push of one repository is told", () => {
  let scan = (~diff="", ~message="", ~files=[]) =>
    () => Ok((Scan.sent(one(~diff, ~message), identifiers), Scan.tracked(files, identifiers)))

  test("a hit in a line sent refuses", () => {
    let judged = Scan.judged(~public=true, ~skip=None, scan(~diff))
    expect(judged->Result.map(({refused}) => refused->Array.length))->toEqual(Ok(2))
  })

  test("a hit in a commit message refuses as a line's does", () => {
    let judged = Scan.judged(~public=true, ~skip=None, scan(~message="see machine.example"))
    expect(judged->Result.map(({refused}) => refused->Array.length))->toEqual(Ok(1))
  })

  test("SKIP=scan passes a hit rather than refusing it", () => {
    let judged = Scan.judged(~public=true, ~skip=Some("scan"), scan(~diff))
    expect(
      judged->Result.map(({refused, passed}) => (refused->Array.length, passed->Array.length)),
    )->toEqual(Ok((0, 2)))
  })

  test("a private repository is not scanned", () => {
    let called = ref(false)
    let judged = Scan.judged(
      ~public=false,
      ~skip=None,
      () => {
        called := true
        Ok(([], []))
      },
    )
    expect((called.contents, judged))->toEqual((false, Ok(Scan.nothing)))
  })

  test("why a repository cannot be scanned is kept", () => {
    expect(Scan.judged(~public=true, ~skip=None, () => Error("no jj")))->toEqual(Error("no jj"))
  })

  test("a tracked hit also being sent is not called already tracked", () => {
    let judged = Scan.judged(
      ~public=true,
      ~skip=None,
      scan(~diff, ~files=[("notes.md", "\n\n\nmachine.example\n"), ("old.md", "192.0.2.1\n")]),
    )
    expect(judged->Result.map(({warned}) => warned))->toEqual(
      Ok([{Scan.place: Line("old.md", 1), identifier: "192.0.2.1", commit: None}]),
    )
  })
})

describe("what a repository tracks", () => {
  test("each hit is named by file and line", () => {
    let tracked = Scan.tracked([("a.txt", "one\ntwo machine.example\n")], identifiers)
    expect(tracked)->toEqual([
      {Scan.place: Line("a.txt", 2), identifier: "machine.example", commit: None},
    ])
    expect(Scan.shown("workspace", tracked->Array.getUnsafe(0)))->toBe(
      "workspace: a.txt:2 holds machine.example",
    )
  })

  test("a file holding a NUL is passed over", () => {
    expect(Scan.tracked([("blob.bin", "machine.example\x00")], identifiers))->toEqual([])
  })
})

test("the list's path reads ~ as the home directory", () => {
  expect(Scan.expanded("~/a/b"))->toBe(Node.join([Scan.homedir(), "a/b"]))
  expect(Scan.expanded("/etc/x"))->toBe("/etc/x")
})
