open Testing

let decided = (name, ~sign="==") => `let a = b ${sign} "${name}"`

describe("the author's account name", () => {
  let say = (line, why, ~file="a.res") => `${file}:${Int.toString(line)}: ${why}`
  let name = Account.name

  test("stands as data and in comments, never in an identifier", () => {
    expect(
      Account.problems(`let link = "example.com/${name}/web" // by ${name}`, ~file="a.res"),
    )->toEqual([])
    expect(Account.problems(`/* ${name} */\nlet ${name}Id = 1`, ~file="a.res"))->toEqual([
      say(2, `${name} is in an identifier`),
    ])
    expect(Account.problems(`let a = "line\nbreak"\nlet ${name} = 1`, ~file="a.res"))->toEqual([
      say(3, `${name} is in an identifier`),
    ])
  })

  test("is never what code decides by", () => {
    let decides = say(1, `code decides by ${name}`)
    expect(Account.problems(decided(name), ~file="a.res"))->toEqual([decides])
    expect(Account.problems(decided(name, ~sign="!=="), ~file="a.ts"))->toEqual([
      say(1, `code decides by ${name}`, ~file="a.ts"),
    ])
    expect(Account.problems(`| "${name}" => 1`, ~file="a.res"))->toEqual([decides])
    expect(Account.problems(`owner.startsWith("${name}")`, ~file="a.ts"))->toEqual([
      say(1, `code decides by ${name}`, ~file="a.ts"),
    ])
    expect(Account.problems(decided(`${name}/web`), ~file="a.res"))->toEqual([])
    expect(Account.problems(`let owners = ["${name}", "other"]`, ~file="a.res"))->toEqual([])
  })

  test("is read in source, not in compiled output or a vendored tree", () => {
    expect(Account.read("scripts/a.res"))->toBe(true)
    expect(Account.read("scripts/a.res.mjs"))->toBe(false)
    expect(Account.read("vendor/lib/a.ts"))->toBe(false)
    expect(Account.read("README.md"))->toBe(false)
  })
})

describe("Twitter", () => {
  let bare = "X"
  let host = ["x", "com"]->Array.join(".")

  test("is named whole in an address, a module and a type", () => {
    let says = line => `a.ts:${Int.toString(line)}: ${host} names Twitter by the bare letter`
    expect(Rebrand.problems(`const a = "https://${host}/home"`, ~file="a.ts"))->toEqual([says(1)])
    expect(Rebrand.problems(`const a = "https://example.com/twitter"`, ~file="a.ts"))->toEqual([])
    expect(Rebrand.problems(`const a = "https://max.example.com"`, ~file="a.ts"))->toEqual([])
    expect(Rebrand.problems(`module ${bare} = {}`, ~file="a.res"))->toEqual([
      `a.res:1: module ${bare} names Twitter by the bare letter`,
    ])
    expect(Rebrand.problems(`module Xml = {}`, ~file="a.res"))->toEqual([])
  })

  test("is named whole in a file or a directory", () => {
    let path = `a path names Twitter by the bare letter; write twitter`
    expect(Rebrand.problems("", ~file="x.res"))->toEqual([`x.res: ${path}`])
    expect(Rebrand.problems("", ~file="spec/x/api.md"))->toEqual([`spec/x/api.md: ${path}`])
    expect(Rebrand.problems("", ~file="x_client.ts"))->toEqual([`x_client.ts: ${path}`])
    expect(Rebrand.problems("", ~file="twitter.md"))->toEqual([])
    expect(Rebrand.problems("", ~file="x86_64.json"))->toEqual([])
  })
})
