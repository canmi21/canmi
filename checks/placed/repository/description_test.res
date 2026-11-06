open Testing

let check = (~isPrivate=false, repo, description) =>
  Description.problems([{repo, description, isPrivate}])

describe("a repository's forge description", () => {
  test("passes one sentence of four to eight words ending in a full stop", () => {
    expect(check("a", Some("A small tool for downloads.")))->toEqual([])
    expect(check("a", Some("One two three four five six seven eight.")))->toEqual([])
    expect(check("a", Some("One two three four.")))->toEqual([])
  })

  test("fails three words, nine words, no full stop, two sentences and none", () => {
    expect(check("a", Some("Too short here.")))->toEqual([
      `a: description "Too short here." has 3 words, not 4 to 8`,
    ])
    expect(check("a", Some("One two three four five six seven eight nine.")))->toEqual([
      `a: description "One two three four five six seven eight nine." has 9 words, not 4 to 8`,
    ])
    expect(check("a", Some("A small tool for downloads")))->toEqual([
      `a: description "A small tool for downloads" does not end in a full stop`,
    ])
    expect(check("a", Some("A tool. Also a library.")))->toEqual([
      `a: description "A tool. Also a library." is more than one sentence`,
    ])
    expect(check("a", None))->toEqual(["a: description has no description"])
  })

  test("lets a private repository go without one, and holds one it has to the rule", () => {
    expect(check(~isPrivate=true, "a", None))->toEqual([])
    expect(check(~isPrivate=true, "a", Some("")))->toEqual([])
    expect(check(~isPrivate=true, "a", Some("Too short here.")))->toEqual([
      `a: description "Too short here." has 3 words, not 4 to 8`,
    ])
  })
})
