open Testing

let table = [
  Credentials.vendor("CLOUDFLARE_TEST_TOKEN_MANAGER", "CLOUDFLARE", Test, "TOKEN_MANAGER"),
  Credentials.neutral("CONTROL_OPERATOR", "CONTROL", Foundation, "OPERATOR"),
  Credentials.neutral("NIX_TEST_SIGNING_KEY", "NIX", Test, "SIGNING_KEY"),
]
let planned = [("NIX_SIGNING_KEY_TEST", "NIX_TEST_SIGNING_KEY")]
let supplied = ["GITHUB_TOKEN"]

let key = name => {Credentials_check.file: "r/secrets.json", name, source: Key}
let used = name => {Credentials_check.file: "r/.github/workflows/w.yml", name, source: Reference}
let problems = (~table=table, names) =>
  Credentials_check.problems(~table, ~planned, ~supplied, names)

describe("the credential names rule", () => {
  test("derives the display and short forms from the variable", () => {
    expect(Credentials.display("CLOUDFLARE_TEST_TOKEN_MANAGER"))->toBe(
      "Cloudflare Test Token Manager",
    )
    expect(Credentials.short("SYSTEMS_READ_KEY_ID"))->toBe("systems-read-key-id")
  })

  test("passes a name in the table, a short form as a key, a planned and a supplied name", () => {
    expect(
      problems([
        key("CONTROL_OPERATOR"),
        key("control-operator"),
        used("CLOUDFLARE_TEST_TOKEN_MANAGER"),
        used("NIX_SIGNING_KEY_TEST"),
        key("NIX_SIGNING_KEY_TEST"),
        used("GITHUB_TOKEN"),
      ]),
    )->toEqual([])
  })

  test("refuses a name the table lacks once per file, and a short form in a workflow", () => {
    expect(problems([key("STRAY_KEY"), key("STRAY_KEY"), used("control-operator")]))->toEqual([
      "r/secrets.json: STRAY_KEY is no credential in model/rules/credentials.res",
      "r/.github/workflows/w.yml: control-operator is no credential in model/rules/credentials.res",
    ])
  })

  test("refuses a vendor-tied name that does not lead with its vendor", () => {
    let wrong = [
      Credentials.vendor("CONTROL_TEST_CLOUDFLARE_TOKEN", "CLOUDFLARE", Test, "CONTROL_TOKEN"),
    ]
    expect(problems(~table=wrong, []))->toEqual([
      "CONTROL_TEST_CLOUDFLARE_TOKEN breaks the order vendor, platform, purpose, which writes CLOUDFLARE_TEST_CONTROL_TOKEN",
      "NIX_SIGNING_KEY_TEST is planned to become NIX_TEST_SIGNING_KEY, which the table does not hold",
    ])
  })

  test("refuses a foundation name that carries a platform word", () => {
    let wrong = [Credentials.neutral("NIX_TEST_SIGNING_KEY", "NIX", Foundation, "TEST_SIGNING_KEY")]
    expect(problems(~table=wrong, []))->toEqual([
      "NIX_TEST_SIGNING_KEY carries a platform word in the foundation, which is the default and names none",
    ])
  })

  test("reads a secrets.json by its keys and a workflow by its secrets, sops left out", () => {
    let tree: Lines.tree = {
      root: "r",
      at: None,
      paths: ["secrets.json", ".github/workflows/w.yml", "other.json"],
      bytes: path =>
        switch path {
        | "secrets.json" => Some(Net.fromText(`{"A_KEY": "ENC[x]", "sops": {"mac": "m"}}`))
        | ".github/workflows/w.yml" =>
          Some(Net.fromText("env:\n  T: ${{ secrets.B_KEY }} ${{ secrets.GITHUB_TOKEN }}\n"))
        | _ => Some(Net.fromText(`{"C_KEY": 1}`))
        },
    }
    expect(Credentials_check.read(tree, ~label="r")->Array.map(({name}) => name))->toEqual([
      "A_KEY",
      "B_KEY",
      "GITHUB_TOKEN",
    ])
  })
})
