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
    expect(Outdated.allowed(text))->toEqual(Map.fromArray([("@types/node", "the \"types\" lag"), ("vite", "two")]))
  })
})
