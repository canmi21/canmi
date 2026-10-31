open Testing

let payload = (command): Payload.t =>
  Dict.fromArray([("tool_input", JSON.Object(Dict.fromArray([("command", JSON.String(command))])))])

describe("a push past the verb", () => {
  test("is found in jj git push and git push, however they are wrapped", () => {
    expect(Push.bypasses("jj git push -b main"))->toEqual(true)
    expect(Push.bypasses("jj -R repos/seam git push --bookmark main"))->toEqual(true)
    expect(Push.bypasses("jj describe -m x && jj new && jj git push -b main"))->toEqual(true)
    expect(Push.bypasses("git push origin main"))->toEqual(true)
    expect(Push.bypasses("git -C repos/seam push"))->toEqual(true)
    expect(Push.bypasses("env FOO=1 git push"))->toEqual(true)
    expect(Push.bypasses("echo $(jj git push)"))->toEqual(true)
  })

  test("is not found in the verb, a fetch, or a word inside a quote", () => {
    expect(Push.bypasses("mise run push monoflake/cloud"))->toEqual(false)
    expect(Push.bypasses("mise run push --dry-run"))->toEqual(false)
    expect(Push.bypasses("jj git fetch"))->toEqual(false)
    expect(Push.bypasses("git pull --rebase"))->toEqual(false)
    expect(Push.bypasses("echo 'jj git push'"))->toEqual(false)
    expect(Push.bypasses("grep -n 'git push' docs/lessons.md"))->toEqual(false)
  })

  test("is not found in a quoted here-document's body, and is in an unquoted one's", () => {
    expect(Push.bypasses("python3 - <<'EOF'\ns = \"run `jj git push` by hand\"\nEOF"))->toEqual(
      false,
    )
    expect(Push.bypasses("cat <<\"EOF\"\njj git push -b main\nEOF\necho done"))->toEqual(false)
    expect(Push.bypasses("cat <<'EOF'\ntext\nEOF\njj git push -b main"))->toEqual(true)
    expect(Push.bypasses("cat <<EOF\n`jj git push`\nEOF"))->toEqual(true)
  })

  test("is refused with the harness's status 2, anything else passed", () => {
    expect(Push.refuse(payload("jj git push -b main")))->toEqual(2)
    expect(Push.refuse(payload("mise run push")))->toEqual(0)
  })
})
