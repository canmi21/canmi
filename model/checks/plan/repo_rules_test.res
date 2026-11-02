open Testing

let held = `[{"name": "a", "says": "x", "doc": "docs/<a>.md", "held": {"check": "shape"}},
  {"name": "b", "says": "y", "doc": "docs/<b>.md", "held": {"pending": "a scan"}},
  {"name": "c", "says": "z", "doc": "docs/<c>.md", "held": {"hook": "hooks/c"}},
  {"name": "d", "says": "w", "doc": "docs/<d>.md", "held": {"gate": "push"}}]`

describe("a repository's own rules", () => {
  test("are model/rules.json, or model/rules/rules.json where only that one is present", () => {
    let root = Node.mkdtempSync(Node.join([Node.tmpdir(), "rules-"]))
    expect(Repo_rules.fileAt(root))->toBe("model/rules.json")
    Node.mkdirAll(Node.join([root, "model", "rules"]))
    Node.writeFileSync(Node.join([root, "model", "rules", "rules.json"]), "[]")
    expect(Repo_rules.fileAt(root))->toBe("model/rules/rules.json")
    Node.writeFileSync(Node.join([root, "model", "rules.json"]), "[]")
    expect(Repo_rules.fileAt(root))->toBe("model/rules.json")
    Node.rmSync(root, {recursive: true, force: true})
  })

  test("read each holder, naming the rule by its repository", () => {
    switch Repo_rules.parse(held, ~owner="fixture/platform") {
    | Ok(rules) =>
      expect(rules->Array.map(rule => rule.name))->toEqual([
        "fixture/platform:a",
        "fixture/platform:b",
        "fixture/platform:c",
        "fixture/platform:d",
      ])
      expect(rules->Array.map(rule => rule.held))->toEqual([
        Check("shape"),
        Pending("a scan"),
        Hook("hooks/c"),
        Gate("push"),
      ])
    | Error(why) => throw(Repo_rules.Bad(why))
    }
  })

  test("refuse a malformed record, an unknown key or holder, an empty owed and non-JSON", () => {
    let refused = text => Repo_rules.parse(text, ~owner="fixture/platform")->Result.isError
    expect(refused(`{"rules": []}`))->toBe(true)
    expect(refused(`[{"name": "a", "says": "x", "doc": "d"}]`))->toBe(true)
    expect(refused(`[{"name": "a", "says": "x", "doc": "d", "held": {"done": "y"}}]`))->toBe(true)
    expect(refused(`[{"name": "a", "says": "x", "doc": "d", "held": {"pending": ""}}]`))->toBe(true)
    expect(
      refused(`[{"name": "a", "says": "x", "doc": "d", "mood": 1, "held": {"pending": "y"}}]`),
    )->toBe(true)
    expect(refused("not json"))->toBe(true)
  })
})
