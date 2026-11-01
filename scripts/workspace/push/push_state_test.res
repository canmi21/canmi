open Testing

describe("push preflight", () => {
  test("asks for exactly the commits on remote main absent from local main", () => {
    let calls = []
    expect(
      Push_state.ready(
        args => {
          calls->Array.push(args)
          Ok("")
        },
      ),
    )->toEqual(Ok())
    expect(calls)->toEqual([
      [
        "log",
        "--no-graph",
        "-r",
        `main..remote_bookmarks(exact:"main", exact:"origin") ~ root()`,
        "-T",
        `commit_id.short() ++ "\\n"`,
      ],
    ])
  })

  test("names every incoming commit and requires reading and checking again", () => {
    expect(Push_state.ready(_ => Ok("aaaaaaaaaaaa\nbbbbbbbbbbbb\n")))->toEqual(
      Error(
        "main@origin has incoming commits aaaaaaaaaaaa, bbbbbbbbbbbb; " ++ "pull, read them, rebase onto main@origin, move main, and check again before pushing",
      ),
    )
  })

  test("refuses a failed graph read rather than treating it as no incoming commits", () => {
    expect(Push_state.ready(_ => Error("cannot resolve main")))->toEqual(
      Error("cannot resolve main"),
    )
  })

  test("collects empty and nonempty outgoing sets before any push", () => {
    expect(
      Push_state.planned(["one", "two"], repo => Ok(repo == "one" ? [] : ["aaaaaaaaaaaa"])),
    )->toEqual(Ok([("one", Some([])), ("two", Some(["aaaaaaaaaaaa"]))]))
  })

  test("discards the entire plan when any repository cannot be inspected", () => {
    let calls = []
    let planned = Push_state.planned(
      ["one", "two", "three"],
      repo => {
        calls->Array.push(repo)
        repo == "two" ? Error("cannot inspect two") : Ok(["aaaaaaaaaaaa"])
      },
    )
    expect(planned)->toEqual(Error("cannot inspect two"))
    expect(calls)->toEqual(["one", "two"])
  })
})
