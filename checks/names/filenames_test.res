open Testing

describe("file and directory names", () => {
  test("passes a router's parameter and group directories, their names held to the shape", () => {
    ["[step]", "[[lang]]", "[...rest]", "(app)", "[sign-in]"]->Array.forEach(
      segment => expect(Filenames.fits(segment, ~file=false))->toBe(true),
    )
  })

  test("refuses a bracketed name off the shape, and brackets on a file", () => {
    ["[Step]", "[step_one]", "[]", "(App)", "[step"]->Array.forEach(
      segment => expect(Filenames.fits(segment, ~file=false))->toBe(false),
    )
    expect(Filenames.fits("[step].ts", ~file=true))->toBe(false)
  })
})
