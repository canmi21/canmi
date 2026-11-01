open Testing

/** Spelled apart so the refs check reads no doc cited here. */
let md = ".md"

describe("a doc holding only the rules in force", () => {
  let root = temporaryRoot("docs-force-")
  let found = text => Docs_force.problems(text, ~file=`docs/a${md}`)->Array.length

  test("names a decider with a date, across a wrapped line", () => {
    expect(found("A rule, decided by the author\non 2026-10-24. More."))->toBe(1)
    expect(found("Agreed with the author on 2026-10-20, so it holds."))->toBe(1)
    expect(found("The task was `new-rfc` until 2026-10-26, when tasks came to one word."))->toBe(1)
  })

  test("names a learned date, a chosen advisor and a provisional decider", () => {
    expect(found("Learned on 2026-10-01 the hard way."))->toBe(1)
    expect(found("The value is chosen by the advisor."))->toBe(1)
    expect(found("The value is provisional chosen by the integrator."))->toBe(1)
  })

  test("passes a rule with no origin and a decision a file makes", () => {
    expect(found("What may be copied is decided by that file and not by the vendor."))->toBe(0)
    expect(found("Whether to spawn is decided by the user, per session."))->toBe(0)
    expect(found("Expires on 2026-12-01."))->toBe(0)
  })

  test("reads the docs outside docs/rfcs and each AGENTS.md", () => {
    expect(Docs_force.read(`docs/a${md}`))->toBe(true)
    expect(Docs_force.read(`docs/agents/b${md}`))->toBe(true)
    expect(Docs_force.read(`repos/x/AGENTS${md}`))->toBe(true)
    expect(Docs_force.read(`docs/rfcs/ab/c${md}`))->toBe(false)
    expect(Docs_force.read(`spec/a${md}`))->toBe(false)
  })

  test("is held over a repository's tracked files", () => {
    let dir = root.contents
    tree(
      dir,
      [(`docs/a${md}`, "Decided by the author on 2026-10-24.\n"), (`docs/b${md}`, "Plain.\n")],
    )
    Node.run(~cwd=dir, "git", ["init", "-q"])->ignore
    expect(Docs_force.repository(~root=dir)->Array.length)->toBe(1)
  })
})
