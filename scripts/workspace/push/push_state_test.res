open Testing

let log = [
  "log",
  "--no-graph",
  "-r",
  `main..remote_bookmarks(exact:"main", exact:"origin") ~ root()`,
  "-T",
  `commit_id.short() ++ " " ++ description.first_line() ++ "\\n"`,
]

describe("push preflight", () => {
  test("asks, with no fetch, for the commits on remote main absent from local main", () => {
    let calls = []
    expect(
      Push_state.ready(
        args => {
          calls->Array.push(args)
          Ok("")
        },
        ~place="apps/rdm",
      ),
    )->toEqual(Ok())
    expect(calls)->toEqual([log])
  })

  test("names every incoming commit by id and subject, with the steps to rebase and check", () => {
    let read = _ => Ok("aaaaaaaaaaaa bump tools\nbbbbbbbbbbbb bump deps\n")
    expect(Push_state.ready(read, ~place="monoflake/driver"))->toEqual(
      Error(
        "main@origin moved, 2 incoming commit(s):\n" ++
        "    aaaaaaaaaaaa bump tools\n    bbbbbbbbbbbb bump deps\n" ++
        "read them, rebase onto main@origin, check again, then push:\n" ++
        "    jj rebase -b main -d main@origin\n" ++
        "    jj bookmark set main -r <your last commit>   (only where main was behind your commits)\n" ++ "    mise run check monoflake/driver\n    mise run push monoflake/driver",
      ),
    )
  })

  test("refuses a failed graph read rather than treating it as no incoming commits", () => {
    let read = _ => Error("cannot resolve main")
    expect(Push_state.ready(read, ~place="x"))->toEqual(Error("cannot resolve main"))
  })

  test("a refused push names CI moving main and the steps to fetch, rebase, check and push", () => {
    expect(Push_state.refused("monoflake/driver"))->toEqual(
      "jj git push failed in monoflake/driver; where main@origin moved, most often by CI's " ++
      "scheduled update, fetch and read what came in, rebase onto it, check again, then push:\n" ++
      "    jj git fetch\n    jj rebase -b main -d main@origin\n" ++ "    mise run check monoflake/driver\n    mise run push monoflake/driver",
    )
  })

  test("a dry run reports the same refusal in the conditional, a push in the plain", () => {
    expect(Push_state.stopped("main@origin moved", ~dry=true))->toEqual(
      "main@origin moved, so a push would push nothing",
    )
    expect(Push_state.stopped("main@origin moved", ~dry=false))->toEqual(
      "main@origin moved, so push pushes nothing",
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
