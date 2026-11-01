open Testing

let source = Node.readFileSync(Node.join([Registry.root, ".github/actions/workspace/action.yml"]))
let steps = Runs.read(source, ~action=true)->Array.flatMap(job => job.steps)
let clone =
  steps
  ->Array.find(step => step.name == "Clone what the stages read beside it")
  ->Option.getOrThrow

let exercise = (~root, ~pin=false, ~scripts=false) => {
  Node.mkdirAll(Node.join([root, "repos/owner/one"]))
  Node.mkdirAll(Node.join([root, "repos/owner/two"]))
  tree(root, [("repos/caller/workspace.toml", pin ? "[versions]\npin = \"pin.yml\"\n" : "")])
  let shell = `
set -e
GITHUB_WORKSPACE="$1"
CALLER=caller
BESIDE='owner/one owner/two'
SCRIPTS="$2"
log="$1/calls"
pnpm() { echo pnpm >> "$log"; }
mise() { echo mise >> "$log"; }
node() { echo node >> "$log"; echo main; }
git() { echo git >> "$log"; }
${clone.run->Option.getOrThrow}
`
  let result = Node.spawnSync(
    "bash",
    ["-c", shell, "action", root, scripts ? "true" : "false"],
    {
      encoding: "utf8",
    },
  )
  expect(result.status)->toBe(Nullable.make(0))
  Landing.disk(~root, "calls")->Option.getOr("")
}

describe("preparing pinned siblings", () => {
  let root = temporaryRoot("sibling-action-")

  test("the named preparation steps require scripts", () => {
    steps
    ->Array.filter(
      step =>
        ["Install the workspace's packages", "Compile the workspace's scripts"]->Array.includes(
          step.name,
        ),
    )
    ->Array.forEach(
      step =>
        expect(step.condition)->toBe(
          JSON.stringify(JSON.Encode.string("inputs.scripts == 'true'")),
        ),
    )
  })

  test("an unpinned caller needs no workspace preparation or pin reader", () => {
    expect(exercise(~root=root.contents))->toBe("")
  })

  test("a pinned caller prepares the workspace once for multiple siblings", () => {
    expect(exercise(~root=root.contents, ~pin=true))->toBe("pnpm\nmise\nnode\nnode\n")
  })

  test("scripts already requested need no second preparation", () => {
    expect(exercise(~root=root.contents, ~pin=true, ~scripts=true))->toBe("node\nnode\n")
  })
})
