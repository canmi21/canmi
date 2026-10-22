open Testing

let front = (~status="draft", ~extra="") =>
  `---
name: "Hue Pairs"
title: Hues come in pairs
status: ${status}
supersedes: []
blocked-by: []
commits: []
references: []${extra}
---

## Question

Why pairs?
`

describe("an RFC's name", () => {
  test("reads its day, place, slug and id", () => {
    expect(Rfc_name.parse("2026-1022-03-hue-pairs-ab3x9.md"))->toEqual(
      Some({day: "2026-1022", order: 3, slug: "hue-pairs", id: "ab3x9"}),
    )
    expect(Rfc_name.format({day: "2026-1022", order: 3, slug: "hue-pairs", id: "ab3x9"}))->toBe(
      "2026-1022-03-hue-pairs-ab3x9.md",
    )
  })

  test("is refused for a day that does not exist, place zero or a short id", () => {
    expect(Rfc_name.parse("2026-0230-01-x-ab3x9.md"))->toEqual(None)
    expect(Rfc_name.parse("2026-1022-00-x-ab3x9.md"))->toEqual(None)
    expect(Rfc_name.parse("2026-1022-01-x-ab3x.md"))->toEqual(None)
    expect(Rfc_name.parse("2026-1022-01-Hue-ab3x9.md"))->toEqual(None)
  })

  test("takes its slug from the name's words", () => {
    expect(Rfc_name.slugOf("The Footing's Interface"))->toBe("the-footing-s-interface")
    expect(Rfc_name.slugOf("  One, Two  "))->toBe("one-two")
  })

  test("draws an id none holds, redrawing a byte past the last whole multiple", () => {
    let bytes = [255, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1]
    let next = ref(0)
    let random = () => {
      let byte = bytes->Array.getUnsafe(next.contents)
      next := next.contents + 1
      byte
    }
    expect(Rfc_name.fresh(["aaaaa"], ~random))->toBe("bbbbb")
  })
})

describe("an RFC's frontmatter", () => {
  test("passes as the format writes it", () => {
    let (read, problems) = Rfc_record.readFront(front())
    expect(problems)->toEqual([])
    expect(read->Option.map(front => front.status))->toEqual(Some("draft"))
  })

  test("names each key missing, unknown or out of form", () => {
    let text = "---\nname: \"\"\ntitle:\nstatus: done\nowner: me\ncommits: [web]\n---\n"
    let (_, problems) = Rfc_record.readFront(text)
    expect(problems)->toEqual([
      "`owner` is not a key the format has",
      "`name` is empty",
      "`title` is empty",
      "`status` is not one of draft, accepted, landed, declined",
      "`commits[0]` is not repo@hash",
      "`references` is missing; write [] for our own idea",
    ])
  })

  test("holds a landed RFC to its commits and every other to none", () => {
    let read = text => Rfc_record.readFront(text)->Pair.first->Option.getOrThrow
    expect(Rfc_record.checkStatus(read(front(~status="landed"))))->toEqual([
      "a landed RFC names at least one commit",
    ])
    let named =
      front(~status="accepted")->String.replace(
        "commits: []",
        "commits: [monoflake/platform@d25effc4]",
      )
    expect(Rfc_record.checkStatus(read(named)))->toEqual([
      "a accepted RFC landed nothing, so `commits` is empty",
    ])
  })

  test("asks a decision of every RFC but a draft, the sections in their order", () => {
    expect(Rfc_record.checkSections("## Question\n", ~status=Some("accepted")))->toEqual([
      "no `## Decision`",
    ])
    expect(
      Rfc_record.checkSections("## Decision\n## Question\n## Decided\n", ~status=Some("draft")),
    )->toEqual([
      "unknown section `Decided`",
      "sections stand out of order; the order is Question, Options, Evidence, Decision",
      "a draft has no `## Decision`; it is `accepted` once decided",
    ])
    expect(
      Rfc_record.checkSections("```\n## Not\n```\n## Question\n", ~status=Some("draft")),
    )->toEqual([])
  })

  test("refuses raw HTML, a directive, and a host or address that could be real", () => {
    expect(Rfc_record.checkPlain("a <b>bold</b> word\n\n::chart{x=1}\n")->Array.length)->toBe(3)
    expect(Rfc_private.check("see https://example.com and docs.example, or `a.b`"))->toEqual([])
    expect(Rfc_private.check("at real.io, mail a@b.org, 10.0.0.1"))->toEqual([
      "mail domain b.org could be real; write a reserved one, as in example.com",
      "host real.io could be real; write a reserved one, as in example.com",
      "address 10.0.0.1 could be real; write a reserved one, as in example.com",
    ])
  })
})

describe("blocked-by", () => {
  let graph = pairs =>
    Map.fromArray(
      pairs->Array.map(((id, status, blockedBy)) => (id, ({status, blockedBy}: Rfc_graph.node))),
    )

  test("finds each cycle once", () => {
    let cyclic = graph([("aaaaa", "draft", ["bbbbb"]), ("bbbbb", "draft", ["aaaaa"])])
    expect(Rfc_graph.cycles(cyclic))->toEqual([["aaaaa", "bbbbb", "aaaaa"]])
  })

  test("reads what is ready and the longest chain each other waits behind", () => {
    let open_ = graph([
      ("aaaaa", "draft", []),
      ("bbbbb", "accepted", ["aaaaa"]),
      ("ccccc", "draft", ["bbbbb", "ddddd"]),
      ("ddddd", "landed", ["eeeee"]),
    ])
    expect(Rfc_graph.ready(open_))->toEqual(["aaaaa"])
    expect(Rfc_graph.chainOf("ccccc", open_))->toEqual(["aaaaa", "bbbbb", "ccccc"])
    expect(Rfc_graph.checkBlockers("ddddd", open_))->toEqual([
      "is blocked by eeeee, which no RFC of its id space holds",
    ])
  })
})

describe("an id space", () => {
  let file = (~repo, ~area="design", ~day="2026-1022", ~order=1, id): Rfc_spaces.file => {
    day,
    order,
    slug: "x",
    id,
    space: "monoflake",
    repo,
    area,
    path: `/w/${repo}/docs/rfcs/${area}/${id}.md`,
    where: `${repo}/${id}.md`,
  }
  let held = entries =>
    Rfc_check.held(
      entries,
      ~strays=[],
      ~areas=["design"],
      ~repos=["workspace", "monoflake/platform"],
      ~exists=(_, hash) => Some(hash == "d25effc4"),
    )->Array.map(problem => problem.says)

  test("holds an id and a place unique across its repositories", () => {
    let entries = [
      {Rfc_check.file: file(~repo="a", "aaaaa"), text: front()},
      {file: file(~repo="b", ~order=2, "aaaaa"), text: front()},
      {file: file(~repo="b", "bbbbb"), text: front()},
    ]
    expect(held(entries))->toEqual([
      "b/aaaaa.md: id aaaaa is also a/aaaaa.md's",
      "b/bbbbb.md: 2026-1022-01 is also a/aaaaa.md's place",
    ])
  })

  test("asks the repository a commit names, and refuses one the registry does not list", () => {
    let landed = commits =>
      front(~status="landed")
      ->String.replace("commits: []", `commits: [${commits}]`)
      ->String.concat("\n## Decision\n\nPairs.\n")
    let entries = [
      {
        Rfc_check.file: file(~repo="a", "aaaaa"),
        text: landed("monoflake/platform@d25effc4, monoflake/platform@0000000, web@d25effc4"),
      },
    ]
    expect(held(entries))->toEqual([
      "a/aaaaa.md: names monoflake/platform@0000000, which its repository does not hold",
      "a/aaaaa.md: names web@d25effc4, whose repository repos/registry.toml does not list",
    ])
  })

  test(
    "keeps a commit in a retired repository as written, and still refuses an unknown one",
    () => {
      let landed = commits =>
        front(~status="landed")
        ->String.replace("commits: []", `commits: [${commits}]`)
        ->String.concat("\n## Decision\n\nPairs.\n")
      let entries = [
        {
          Rfc_check.file: file(~repo="a", "aaaaa"),
          text: landed("platform@0000000, infra@0000000, gone@0000000"),
        },
      ]
      expect(held(entries))->toEqual([
        "a/aaaaa.md: names gone@0000000, whose repository repos/registry.toml does not list",
      ])
    },
  )
})
