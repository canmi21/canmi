open Testing

describe("pruning a build's leftovers", () => {
  test("removes a module whose source is gone, under the compiled directories alone", () => {
    let root = Node.mkdtempSync(Node.join([Node.tmpdir(), "prune-"]))
    let write = name => {
      let path = Node.join([root, name])
      Node.mkdirAll(Node.dirname(path))
      Node.writeFileSync(path, "x\n")
    }
    Node.writeFileSync(
      Node.join([root, "rescript.json"]),
      `{"sources":[{"dir":"deep","subdirs":true},{"dir":"flat"},"plain"]}`,
    )
    [
      "deep/kept.res",
      "deep/kept.res.mjs",
      "deep/moved.res.mjs",
      "deep/inner/moved.res.mjs",
      "flat/moved.res.mjs",
      "flat/inner/moved.res.mjs",
      "plain/moved.res.mjs",
      "elsewhere/moved.res.mjs",
    ]->Array.forEach(write)
    expect(Prune.prune(root)->Array.toSorted(String.compare))->toEqual([
      "deep/inner/moved.res.mjs",
      "deep/moved.res.mjs",
      "flat/moved.res.mjs",
      "plain/moved.res.mjs",
    ])
    expect(Node.existsSync(Node.join([root, "deep/kept.res.mjs"])))->toBe(true)
    expect(Node.existsSync(Node.join([root, "elsewhere/moved.res.mjs"])))->toBe(true)
    expect(Node.existsSync(Node.join([root, "flat/inner/moved.res.mjs"])))->toBe(true)
  })
})
