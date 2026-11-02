open Testing

let bash = (cwd, command): Payload.t =>
  Dict.fromArray([
    ("tool_name", JSON.String("Bash")),
    ("cwd", JSON.String(cwd)),
    ("tool_input", JSON.Object(Dict.fromArray([("command", JSON.String(command))]))),
  ])

describe("trash on a cache", () => {
  test("is refused for each cache path, whole or inside", () => {
    expect(Trash.refuse(bash("/w/repo", "trash target")))->toBe(2)
    expect(Trash.refuse(bash("/w/repo", "trash -v node_modules/x a.log")))->toBe(2)
    expect(Trash.refuse(bash("/w/repo", "trash lib/bs")))->toBe(2)
    expect(Trash.refuse(bash("/w/repo", "cd x && trash ./dist")))->toBe(2)
    expect(Trash.reason(Trash.resolved("a.o", ~cwd="/w/repo/target"))->Option.isSome)->toBe(true)
  })

  test("names the clean of the cache", () => {
    expect(
      Trash.reason("/w/repo/target/debug")->Option.getOr("")->String.includes("cargo clean"),
    )->toBe(true)
  })

  test("is refused for the pnpm global store", () => {
    expect(Trash.refuse(bash("/w", "trash /Users/x/Library/pnpm/store/v10")))->toBe(2)
    expect(Trash.refuse(bash("/w", "trash .pnpm-store")))->toBe(2)
  })

  test("passes an ordinary path, a similar name and another program", () => {
    expect(Trash.refuse(bash("/w/repo", "trash old.log src")))->toBe(0)
    expect(Trash.refuse(bash("/w/repo", "trash targets distant")))->toBe(0)
    expect(Trash.refuse(bash("/w/repo", "ls target")))->toBe(0)
    expect(Trash.refuse(bash("/w/repo", "echo trash target")))->toBe(0)
  })
})
