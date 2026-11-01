open Testing

describe("scan input failures", () => {
  test("reads every outgoing diff and message separately", () => {
    let calls = []
    let commits = Scan.outgoingWith(
      args => {
        calls->Array.push(args)
        switch args {
        | ["log", "--no-graph", "-r", _, "-T", template] if template != "description" =>
          Ok("aaaaaaaaaaaaaaaa\nbbbbbbbbbbbbbbbb\n")
        | ["diff", "-r", id, "--git"] => Ok(`diff ${id}`)
        | ["log", "--no-graph", "-r", id, "-T", "description"] => Ok(`message ${id}`)
        | _ => Error("unexpected read")
        }
      },
    )
    expect(commits)->toEqual(
      Ok([
        {
          Scan.id: "aaaaaaaaaaaa",
          diff: "diff aaaaaaaaaaaaaaaa",
          message: "message aaaaaaaaaaaaaaaa",
        },
        {id: "bbbbbbbbbbbb", diff: "diff bbbbbbbbbbbbbbbb", message: "message bbbbbbbbbbbbbbbb"},
      ]),
    )
    expect(calls->Array.length)->toBe(5)
    expect(calls[0])->toEqual(
      Some(["log", "--no-graph", "-r", Scan.range, "-T", `commit_id ++ "\\n"`]),
    )
  })

  test("a failed outgoing list refuses the scan", () => {
    expect(Scan.outgoingWith(_ => Error("list failed")))->toEqual(Error("list failed"))
  })

  test("a failed diff or message refuses without reading later commits", () => {
    ["diff", "message"]->Array.forEach(
      failed => {
        let calls = []
        let result = Scan.outgoingWith(
          args => {
            calls->Array.push(args)
            switch args {
            | ["log", "--no-graph", "-r", _, "-T", template] if template != "description" =>
              Ok("aaaaaaaaaaaaaaaa\nbbbbbbbbbbbbbbbb\n")
            | ["diff", "-r", _, "--git"] => failed == "diff" ? Error(failed) : Ok("")
            | _ => Error(failed)
            }
          },
        )
        expect(result)->toEqual(Error(failed))
        expect(calls->Array.length)->toBe(failed == "diff" ? 2 : 3)
      },
    )
  })

  test("a failed tracked file list never reads content", () => {
    let called = ref(false)
    expect(
      Scan.filesWith(
        _ => Error("list failed"),
        _ => {
          called := true
          Ok("")
        },
      ),
    )->toEqual(Error("list failed"))
    expect(called.contents)->toBe(false)
  })

  test("an unreadable tracked file refuses rather than silently shortening the scan", () => {
    let calls = []
    let result = Scan.filesWith(
      _ => Ok("one.txt\ntwo.txt\nthree.txt\n"),
      path => {
        calls->Array.push(path)
        path == "two.txt" ? Error("cannot read tracked file two.txt") : Ok("machine.example")
      },
    )
    expect(result)->toEqual(Error("cannot read tracked file two.txt"))
    expect(calls)->toEqual(["one.txt", "two.txt"])
  })

  test("reads all listed files and ignores only empty list lines", () => {
    expect(
      Scan.filesWith(
        args => {
          expect(args)->toEqual(["file", "list"])
          Ok("one.txt\n\ntwo.txt\n")
        },
        path => Ok(path),
      ),
    )->toEqual(Ok([("one.txt", "one.txt"), ("two.txt", "two.txt")]))
    expect(Scan.filesWith(_ => Ok(""), _ => Error("unexpected read")))->toEqual(Ok([]))
  })
})
