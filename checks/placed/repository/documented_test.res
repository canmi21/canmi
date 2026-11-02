open Testing

let quad = octets => octets->Array.map(octet => Int.toString(octet))->Array.join(".")
let host = labels => labels->Array.join(".")

describe("a test's addresses and domains", () => {
  let wrote = (found, ~line=1) =>
    `a_test.ts:${Int.toString(line)}: a test writes ${found}, outside documentation`
  let problems = (text, ~file="a_test.ts") => Documented.problems(text, ~file)

  test("are the documentation blocks, a private block it is allowed and loopback", () => {
    expect(problems(`ok("${quad([192, 0, 2, 7])}", "${quad([203, 0, 113, 9])}")`))->toEqual([])
    expect(problems(`ok("${quad([198, 51, 100, 1])}", "${quad([10, 200, 4, 5])}")`))->toEqual([])
    expect(problems(`ok("${quad([127, 0, 0, 1])}", "${quad([255, 255, 255, 0])}")`))->toEqual([])
    expect(problems(`ok("${quad([8, 8, 4, 4])}")`))->toEqual([wrote(quad([8, 8, 4, 4]))])
    expect(problems(`\nok("${quad([10, 0, 0, 2])}")`))->toEqual([
      wrote(quad([10, 0, 0, 2]), ~line=2),
    ])
    expect(problems(`ok("${quad([300, 1, 1, 1])}")`))->toEqual([])
    expect(problems(`ok("version ${quad([1, 2, 3, 4, 5])}")`))->toEqual([])
  })

  test("are example domains, a reserved suffix and the subdomains of both", () => {
    expect(
      problems(`ok("${host(["a", "example", "com"])}", "${host(["b", "test"])}")`),
    )->toEqual([])
    expect(problems(`ok("https://${host(["api", "example", "org"])}/v1")`))->toEqual([])
    expect(problems(`ok("https://${host(["real", "com"])}/v1")`))->toEqual([
      wrote(host(["real", "com"])),
    ])
    expect(problems(`ok("${host(["notexample", "com"])}")`))->toEqual([
      wrote(host(["notexample", "com"])),
    ])
    expect(problems(`ok(profile.dev, Ports.dev)`))->toEqual([])
  })

  test("are read in a test and a fixture, and in a Rust file from its test module", () => {
    let outside = quad([8, 8, 4, 4])
    expect(problems(outside, ~file="src/a.ts"))->toEqual([])
    expect(problems(outside, ~file="tests/data.json"))->toEqual([
      `tests/data.json:1: a test writes ${outside}, outside documentation`,
    ])
    expect(problems(outside, ~file="app/fixtures/a.txt"))->toEqual([
      `app/fixtures/a.txt:1: a test writes ${outside}, outside documentation`,
    ])
    expect(
      problems(`let a = "${outside}";\n#[cfg(test)]\nlet b = "${outside}";`, ~file="a.rs"),
    )->toEqual([`a.rs:3: a test writes ${outside}, outside documentation`])
    expect(problems(outside, ~file="tests/data.lock"))->toEqual([])
  })
})
