open Testing

describe("a move put back", () => {
  let root = temporaryRoot("reinstall-")

  test("installs each pnpm lockfile again where it lies, and nothing else", () => {
    let calls = Node.join([root.contents, "calls"])
    tree(
      root.contents,
      [
        ("bin/pnpm", `#!/bin/sh\nprintf '%s %s\\n' "$(basename "$PWD")" "$*" >> '${calls}'\n`),
        ("repo/pnpm-lock.yaml", ""),
        ("repo/cloudflare/pnpm-lock.yaml", ""),
        ("repo/Cargo.lock", ""),
      ],
    )
    Node.run("chmod", ["+x", Node.join([root.contents, "bin/pnpm"])])->ignore
    let path = Node.env->Dict.get("PATH")->Option.getOr("")
    Node.env->Dict.set("PATH", Node.join([root.contents, "bin"]) ++ ":" ++ path)
    Reinstall.after(
      Node.join([root.contents, "repo"]),
      ["pnpm-lock.yaml", "Cargo.lock", "cloudflare/pnpm-lock.yaml", "package.json"],
    )
    Node.env->Dict.set("PATH", path)
    expect(Node.readFileSync(calls))->toBe(
      "repo install --frozen-lockfile --prefer-offline\n" ++ "cloudflare install --frozen-lockfile --prefer-offline\n",
    )
  })
})
