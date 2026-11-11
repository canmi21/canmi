open Testing

describe("a version", () => {
  test("sorts by its numbers, a release above its prerelease", () => {
    expect(["1.10.0", "1.9.0", "1.10.0-rc.1"]->Array.toSorted(Outdated.order))->toEqual([
      "1.9.0",
      "1.10.0-rc.1",
      "1.10.0",
    ])
    expect(Outdated.compare("2.0.0", "2.0.0"))->toBe(0)
  })

  test("major is the part a caret range holds", () => {
    expect(Outdated.major("4.13.12"))->toBe("4")
    expect(Outdated.major("0.28.2"))->toBe("0.28")
    expect(Outdated.major("0.0.3"))->toBe("0.0.3")
  })

  test("allowed at two majors is what versions.toml says, with its reason", () => {
    let text = "[several]\n# why\n\"@types/node\" = \"the \\\"types\\\" lag\"\nvite = \"two\"\n[other]\nx = \"y\"\n"
    expect(Outdated.allowed(text))->toEqual(
      Map.fromArray([("@types/node", "the \"types\" lag"), ("vite", "two")]),
    )
  })
})

describe("an aliased package", () => {
  let listed = `[{"name": "@monoflake/console", "devDependencies": {
    "typescript": {"from": "typescript", "version": "6.0.3"},
    "@typescript/native": {"from": "typescript", "version": "7.0.2"},
    "vite": {"version": "8.1.0"},
    "lib": {"from": "lib", "version": "link:../lib"}
  }}]`
  let outdated = `{"typescript": {"current": "6.0.3", "latest": "7.0.2", "wanted": "6.0.3",
    "dependentPackages": [{"name": "@monoflake/console"}]},
    "vite": {"current": "8.1.0", "latest": "9.0.0", "wanted": "8.1.0",
    "dependentPackages": [{"name": "@monoflake/console"}]}}`

  test("counts as the package it names, at each version held", () => {
    let held = Outdated.heldOf(listed)
    expect(held->Outdated.keys->Outdated.sorted)->toEqual(["typescript", "vite"])
    expect(held->Map.get("typescript")->Option.mapOr([], Outdated.byVersion))->toEqual([
      "6.0.3",
      "7.0.2",
    ])
  })

  test("is held at its latest, so update --major never takes it, allowed or not", () => {
    let report = several =>
      Outdated.reportOf(Outdated.heldOf(listed), Outdated.outdatedFrom(outdated), several, true)
    expect(report(Map.make()))->toEqual(["vite"])
    expect(report(Map.fromArray([("typescript", "two compilers")])))->toEqual(["vite"])
  })

  test("is reported allowed at two majors where versions.toml says why", () => {
    let lines =
      Outdated.reportOf(
        Outdated.heldOf(listed),
        Outdated.outdatedFrom(outdated),
        Map.fromArray([("typescript", "two compilers")]),
        false,
      )->Array.join("\n")
    expect(lines->String.includes("8.1.0 -> 9.0.0"))->toBe(true)
    expect(lines->String.includes("typescript 6.0.3 -> 7.0.2"))->toBe(false)
    expect(lines->String.includes("allowed at several majors: typescript"))->toBe(true)
    expect(lines->String.includes("because two compilers"))->toBe(true)
    expect(lines->String.includes("warning"))->toBe(false)
  })
})
