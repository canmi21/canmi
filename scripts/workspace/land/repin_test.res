open Testing

setConfig({"testTimeout": 30000})

let first = "1111111111111111111111111111111111111111"
let second = "2222222222222222222222222222222222222222"
let pin = commit => `  ref: ${commit} # monoflake/platform@main\r\n`
let declaration = "[versions]\nrepository = \"../platform\"\npin = \"pin.yml\"\n"

describe("repinning text", () => {
  test("keeps the comment and every other line byte for byte", () => {
    let before = `name: setup\r\nref: ${first} # another/repository@main\n`
    let after = `\r\n${pin(first)}last line`
    expect(
      Repin.repinned(before ++ pin(first) ++ after, ~repository="../platform", ~commit=second),
    )->toBe(before ++ pin(second) ++ after)
  })

  test("keeps text without a matching pin", () => {
    let text = `ref: ${first} # another/repository@main\n`
    expect(Repin.repinned(text, ~repository="../platform", ~commit=second))->toBe(text)
  })
})

describe("moving a sibling pin", () => {
  let root = temporaryRoot("land-pin-")
  let jj = (root, args) => {
    let answer = Onset.read(~root, args)
    expect(answer->Option.isSome)->toBe(true)
    answer->Option.getOr("")
  }

  test("moves to main at origin once and then reports none", () => {
    let root = root.contents
    let origin = Node.join([root, "origin"])
    let sibling = Node.join([root, "platform"])
    let own = Node.join([root, "driver"])
    Node.mkdirAll(origin)
    Node.env->Dict.set("JJ_USER", "test")
    Node.env->Dict.set("JJ_EMAIL", "test@localhost")
    jj(origin, ["git", "init", "--colocate"])->ignore
    tree(origin, [("one.txt", "one\n")])
    jj(origin, ["commit", "-m", "chore: begin"])->ignore
    jj(origin, ["bookmark", "set", "main", "-r", "@-"])->ignore
    let target = jj(origin, ["log", "-r", "main", "--no-graph", "-T", "commit_id"])
    jj(root, ["git", "clone", origin, sibling])->ignore
    tree(sibling, [("one.txt", "two\n")])
    jj(sibling, ["commit", "-m", "chore: advance locally"])->ignore
    jj(sibling, ["bookmark", "set", "main", "-r", "@-"])->ignore
    expect(jj(sibling, ["log", "-r", "main", "--no-graph", "-T", "commit_id"]) != target)->toBe(
      true,
    )
    tree(own, [("workspace.toml", declaration), ("pin.yml", pin(first))])
    expect(Repin.moved(~root=own))->toEqual(Ok(Some((first, target, "pin.yml"))))
    expect(Node.readFileSync(Node.join([own, "pin.yml"])))->toBe(pin(target))
    expect(Repin.moved(~root=own))->toEqual(Ok(None))
  })

  test("reports none when either version setting is absent", () => {
    let root = root.contents
    expect(Repin.moved(~root))->toEqual(Ok(None))
    tree(root, [("workspace.toml", "[versions]\nrepository = \"../platform\"\n")])
    expect(Repin.moved(~root))->toEqual(Ok(None))
    tree(root, [("workspace.toml", "[versions]\npin = \"pin.yml\"\n")])
    expect(Repin.moved(~root))->toEqual(Ok(None))
  })

  test("names a missing or malformed pin without writing it", () => {
    let root = root.contents
    tree(root, [("workspace.toml", declaration)])
    let error = Error("pin.yml pins no commit of ../platform")
    expect(Repin.moved(~root))->toEqual(error)
    let text = "ref: main # monoflake/platform@main\n"
    tree(root, [("pin.yml", text)])
    expect(Repin.moved(~root))->toEqual(error)
    expect(Node.readFileSync(Node.join([root, "pin.yml"])))->toBe(text)
  })

  test("names an unreadable sibling without changing the pin", () => {
    let own = Node.join([root.contents, "driver"])
    tree(own, [("workspace.toml", declaration), ("pin.yml", pin(first))])
    expect(Repin.moved(~root=own))->toEqual(Error("../platform cannot be read at main@origin"))
    expect(Node.readFileSync(Node.join([own, "pin.yml"])))->toBe(pin(first))
  })
})
