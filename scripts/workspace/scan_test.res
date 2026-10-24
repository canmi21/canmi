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

describe("what a push sends", () => {
  test("the list is read one identifier per line, blank lines passed over", () => {
    expect(identifiers)->toEqual(["machine.example", "192.0.2.1"])
  })

  test("a hit in an added line is found and refuses the push", () => {
    let sent = Scan.sent(~diff, ~messages="", identifiers)
    expect(sent)->toEqual([
      {Scan.place: Line("notes.md", 2), identifier: "machine.example"},
      {place: Line("new.txt", 2), identifier: "192.0.2.1"},
    ])
    let (passed, refused) = Scan.verdict(sent, ~skip=None)
    expect((passed, refused->Array.length))->toEqual(([], 2))
    expect(Scan.shown("canmi/lib", refused->Array.getUnsafe(0)))->toBe(
      "canmi/lib: notes.md:2 holds machine.example",
    )
  })

  test("a word that merely contains an identifier is not a hit", () => {
    expect(Scan.holds("submachine.example_x", "machine.example"))->toBe(false)
    expect(Scan.holds("machine.examples", "machine.example"))->toBe(false)
    expect(Scan.holds("1192.0.2.1", "192.0.2.1"))->toBe(false)
    expect(Scan.holds("(machine.example)", "machine.example"))->toBe(true)
    expect(Scan.holds("xmachine.example machine.example", "machine.example"))->toBe(true)
  })

  test("a removed line or a header is not what is sent", () => {
    let removed = "--- a/x\n+++ b/x\n@@ -1 +0,0 @@\n-machine.example"
    expect(Scan.sent(~diff=removed, ~messages="", identifiers))->toEqual([])
  })

  test("a hit in a commit message is found", () => {
    let sent = Scan.sent(~diff="", ~messages="docs: name the host\n\nsee 192.0.2.1\n", identifiers)
    expect(sent)->toEqual([{Scan.place: Message, identifier: "192.0.2.1"}])
    expect(Scan.shown("workspace", sent->Array.getUnsafe(0)))->toBe(
      "workspace: a commit message holds 192.0.2.1",
    )
  })

  test("SKIP naming the scan passes a hit, and only the scan", () => {
    let sent = Scan.sent(~diff, ~messages="", identifiers)
    let (passed, refused) = Scan.verdict(sent, ~skip=Some("verify, scan"))
    expect((passed->Array.length, refused))->toEqual((2, []))
    expect(Scan.verdict(sent, ~skip=Some("verify"))->Pair.second->Array.length)->toBe(2)
    expect(Scan.verdict(sent, ~skip=Some("scanned"))->Pair.second->Array.length)->toBe(2)
  })
})

describe("what a repository tracks", () => {
  test("each hit is named by file and line", () => {
    expect(Scan.tracked([("a.txt", "one\ntwo machine.example\n")], identifiers))->toEqual([
      {Scan.place: Line("a.txt", 2), identifier: "machine.example"},
    ])
  })

  test("a file holding a NUL is passed over", () => {
    expect(Scan.tracked([("blob.bin", "machine.example\x00")], identifiers))->toEqual([])
  })
})

test("the list's path reads ~ as the home directory", () => {
  expect(Scan.expanded("~/a/b"))->toBe(Node.join([Scan.homedir(), "a/b"]))
  expect(Scan.expanded("/etc/x"))->toBe("/etc/x")
})
