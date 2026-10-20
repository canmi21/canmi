open Testing

/** Why `parse` refused what was typed, or None where it took it. */
let refused = argv =>
  try {
    Repos.parse(argv)->ignore
    None
  } catch {
  | Registry.Refused(why) => Some(why)
  }

describe("what a verb was asked", () => {
  test("a bare verb is the workspace alone, a name that repository", () => {
    let bare = Repos.parse(["pull"])
    expect((bare.name, bare.everything))->toEqual((None, false))
    let named = Repos.parse(["push", "apps/rdm", "--dry-run"])
    expect((named.name, named.dry))->toEqual((Some("apps/rdm"), true))
  })

  test("the workspace's own check takes its parts and --pending", () => {
    expect(Repos.parse(["verify", "workspace", "words", "names"]).parts)->toEqual([
      "words",
      "names",
    ])
    expect(Repos.parse(["verify", "workspace", "--pending"]).parts)->toEqual(["--pending"])
  })

  test("what the verb would not act on is refused rather than dropped", () => {
    expect(refused(["fmt", "a", "b"]))->toEqual(Some("one name at most; b would have been ignored"))
    expect(refused(["verify", "apps/rdm", "words"])->Option.isSome)->toBe(true)
    expect(refused(["pull", "--major"])->Option.isSome)->toBe(true)
    expect(refused(["list", "--all"])->Option.isSome)->toBe(true)
    expect(refused(["fmt", "--dry"]))->toEqual(Some("unknown option --dry"))
    expect(refused(["verify", "--pending"])->Option.isSome)->toBe(true)
  })

  test("publish hands what follows the name on unread, -n spelled out", () => {
    expect(Repos.parse(["publish", "canmi/web", "--live", "-n"]).passed)->toEqual([
      "--live",
      "--dry-run",
    ])
  })
})
