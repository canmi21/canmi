open Testing

let source = Node.readFileSync(Node.join([Registry.root, ".github/actions/workspace/action.yml"]))
let steps = Runs.read(source, ~action=true)->Array.flatMap(job => job.steps)

/** What `prepare` ran for two siblings, each call as one line, the reference answering `ref`. */
let exercise = (~root, ~pin=false, ~ref="main", ~failing="") => {
  Node.mkdirAll(Node.join([root, "repos/owner/one"]))
  tree(root, [("repos/caller/workspace.toml", pin ? "[versions]\npin = \"pin.yml\"\n" : "")])
  tree(root, [("repos/owner/one/package.json", "{}")])
  let calls = []
  let tools: Siblings.tools = {
    run: (~cwd, command, args) => {
      let call = `${cwd->Option.mapOr("", Node.basename)}> ${command} ${args->Array.join(" ")}`
      calls->Array.push(call)
      call->String.includes(failing) && failing != "" ? 1 : 0
    },
    reference: (~root as _, ~sibling as _) => ref,
  }
  let status = Siblings.prepare(
    ~workspace=root,
    ~caller="caller",
    ~beside="owner/one owner/two",
    tools,
  )
  (status, calls->Array.map(call => call->String.replaceAll(root, "W")))
}

describe("cloning what the stages read beside the caller", () => {
  let root = temporaryRoot("siblings-")

  test("clones what is absent and installs where a package.json is", () => {
    let (status, calls) = exercise(~root=root.contents)
    expect(status)->toBe(0)
    expect(calls)->toEqual([
      "> git clone --depth 1 --branch main https://github.com/owner/two W/repos/owner/two",
      "one> pnpm install --frozen-lockfile",
    ])
  })

  test("an unpinned caller never moves a sibling", () => {
    let (_, calls) = exercise(~root=root.contents, ~ref="abc")
    expect(calls->Array.some(call => call->String.includes("checkout")))->toBe(false)
  })

  test("a pinned caller moves each sibling to the pinned commit", () => {
    let (_, calls) = exercise(~root=root.contents, ~pin=true, ~ref="abc")
    expect(calls->Array.filter(call => call->String.includes("FETCH_HEAD"))->Array.length)->toBe(2)
    expect(calls->Array.includes("one> git fetch --depth 1 origin abc"))->toBe(true)
  })

  test("a pin at main moves nothing", () => {
    let (_, calls) = exercise(~root=root.contents, ~pin=true)
    expect(calls->Array.some(call => call->String.includes("fetch")))->toBe(false)
  })

  test("a failed command stops the run with its status", () => {
    let (status, calls) = exercise(~root=root.contents, ~failing="clone")
    expect(status)->toBe(1)
    expect(calls->Array.length)->toBe(1)
  })
})

describe("the action's clone step", () => {
  let index = name => steps->Array.findIndex(step => step.name == name)
  let build = "Compile the workspace's scripts"

  test("is one call to the script, after the step that builds the scripts", () => {
    let clone = steps->Array.find(step => step.name == "Clone what the stages read beside it")
    expect(clone->Option.flatMap(step => step.run))->toEqual(
      Some("node .github/actions/workspace/siblings.res.mjs"),
    )
    expect(index(build) < index("Clone what the stages read beside it"))->toBe(true)
  })

  test("the preparation steps run for scripts or for a caller with a path", () => {
    [build, "Install the workspace's packages"]->Array.forEach(
      name =>
        expect(
          steps->Array.find(step => step.name == name)->Option.map(step => step.condition),
        )->toEqual(
          Some(JSON.stringify(JSON.Encode.string("inputs.scripts == 'true' || inputs.path != ''"))),
        ),
    )
  })
})
