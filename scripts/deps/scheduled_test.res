open Testing

describe("a scheduled update's held sources", () => {
  test("reads release sources rather than repository names and removes duplicates", () => {
    expect(
      Scheduled.heldSources(
        "update workspace\nwarning: workspace holds back its pins from actions/checkout, jdx/mise-action, whose releases were not read; the rest that moved is kept\nwarning: monoflake/machine holds back its pins from jdx/mise-action, NixOS/nixpkgs, whose releases were not read; the rest that moved is kept\n",
      ),
    )->toEqual(["actions/checkout", "jdx/mise-action", "NixOS/nixpkgs"])
  })

  test("ignores unrelated output and an empty run", () => {
    expect(Scheduled.heldSources("warning: another warning\nupdate passed\n"))->toEqual([])
    expect(Scheduled.heldSources(""))->toEqual([])
  })
})

describe("a scheduled update's changed paths", () => {
  test("reads staged, unstaged, deleted and untracked paths", () => {
    expect(
      Scheduled.changedPaths(
        " M Cargo.lock\x00M  pnpm-lock.yaml\x00 D gone.lock\x00?? new.lock\x00",
      ),
    )->toEqual(["Cargo.lock", "pnpm-lock.yaml", "gone.lock", "new.lock"])
  })

  test("keeps rename and copy destinations and skips their original paths", () => {
    expect(
      Scheduled.changedPaths(
        "R  new.lock\x00old.lock\x00 C copied.lock\x00source.lock\x00 M last.lock\x00",
      ),
    )->toEqual(["new.lock", "copied.lock", "last.lock"])
  })

  test("preserves spaces, quotes, arrows, Unicode and newlines in paths", () => {
    expect(
      Scheduled.changedPaths(
        "??  spaced.lock \x00 M a -> b.lock\x00?? \"quoted\".lock\x00 M café\n.lock\x00",
      ),
    )->toEqual([" spaced.lock ", "a -> b.lock", "\"quoted\".lock", "café\n.lock"])
  })

  test("an empty status has no moved paths", () => {
    expect(Scheduled.changedPaths(""))->toEqual([])
  })
})
