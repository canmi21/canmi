open Testing

let found = subject => History.problems(subject)->Array.length

describe("a subject in the imperative mood", () => {
  test("refuses a past form and a third-person form", () => {
    expect(found("feat: added a part"))->toBe(1)
    expect(found("fix: built the tree"))->toBe(1)
    expect(found("feat: adds a part"))->toBe(1)
    expect(found("fix: removes the pin"))->toBe(1)
  })

  test("passes the imperative and the words that only look otherwise", () => {
    expect(found("feat: add a part"))->toBe(0)
    expect(found("fix: need a pin"))->toBe(0)
    expect(found("docs: focus the guide"))->toBe(0)
    expect(found("fix: bypass the guard"))->toBe(0)
    expect(found("docs: this is a note"))->toBe(0)
  })
})
