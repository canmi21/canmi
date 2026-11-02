/**
 * `push-declared` and `push-workflows-declared`, model/rules/toolchain.res, a repository's
 * workflows that run on a push read against its `[push]`, docs/agents/pushing.md.
 */
let workflow = /^\.github\/workflows\/([^\/]+\.ya?ml)$/

/** Whether a workflow's text runs on a push, its `on` a name, a list or a table. */
let runsOnPush = (text: string) =>
  try {
    switch Yaml.parse(text)->JSON.Decode.object->Option.flatMap(fields => fields->Dict.get("on")) {
    | Some(String(event)) => event == "push"
    | Some(Array(events)) => events->Array.includes(JSON.Encode.string("push"))
    | Some(Object(events)) => events->Dict.get("push")->Option.isSome
    | _ => false
    }
  } catch {
  | JsExn(_) => false
  }

/** Each way `push` and `workflows`, each a file name with whether it runs on a push, disagree. */
let problems = (~push: Project.push, ~workflows: array<(string, bool)>): array<string> => {
  let ci = push.ci->Option.getOr([])
  let named = Array.concat(ci, push.release)
  Array.concat(
    [
      push.stated ? [] : ["[push] gives no visibility"],
      push.ci == None ? ["[push] gives no ci, the workflows a push starts"] : [],
    ]->Array.flat,
    Array.concat(
      workflows->Array.filterMap(((name, pushes)) =>
        pushes && !(named->Array.includes(name))
          ? Some(`${name} runs on a push and is not declared under [push]`)
          : None
      ),
      named->Array.filterMap(name =>
        switch workflows->Array.find(((file, _)) => file == name) {
        | None => Some(`[push] names ${name}, which is no workflow`)
        | Some((_, false)) if ci->Array.includes(name) =>
          Some(`[push] ci names ${name}, which does not run on a push`)
        | Some(_) => None
        }
      ),
    ),
  )
}

/**
 * The workspace's, which has no workspace.toml, declares `Toolchain.rootPush` and releases none.
 */
let bare: Project.push = {
  visibility: Project.public,
  stated: true,
  ci: Some(Toolchain.rootPush),
  release: [],
}

/** The workflows of the tree at `root`, each by its file name with whether it runs on a push. */
let workflows = (~root) =>
  Lines.tracked(root)->Array.filterMap(path =>
    switch workflow->RegExp.exec(path)->Option.map(RegExp.Result.matches) {
    | Some([Some(name)]) => Some((name, runsOnPush(Node.readFileSync(Node.join([root, path])))))
    | _ => None
    }
  )

/** The repository at `root`'s push declarations against its workflows, `label` naming it. */
let found = (~root, ~label): array<string> => {
  let declared = Node.existsSync(Node.join([root, "workspace.toml"]))
    ? Project.read(root)->Result.map(declared => declared.push)
    : Ok(bare)
  declared->Result.mapOr([], push =>
    problems(~push, ~workflows=workflows(~root))->Array.map(why => `${label}: ${why}`)
  )
}

/** The workspace's and every active repository's. */
let main = (): array<string> =>
  Array.concat(
    found(~root=Registry.root, ~label="workspace"),
    Waiting.active()->Array.flatMap(path =>
      found(~root=Node.join([Registry.repos, path]), ~label=path)
    ),
  )
