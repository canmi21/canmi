/**
 * The repositories of this workspace, `repos/registry.toml`, each path under `repos/` to its
 * `user:repo`. `mise.toml`'s `config_roots` repeats the set, and `check` holds the two to the disk.
 */
let root = Node.resolve([Node.dirname(Node.fileURLToPath(Node.importMetaUrl)), "..", ".."])
let repos = Node.join([root, "repos"])
let registryFile = Node.join([repos, "registry.toml"])
let config = Node.join([root, "mise.toml"])

exception Refused(string)
let fail = why => throw(Refused(why))

let remote = /^[A-Za-z0-9][\w.-]*:[\w.-]+$/
let pathKey = /^[\w.-]+(\/[\w.-]+)*$/

/** path -> (user, repo), in the order the file gives them. */
let registry = (): array<(string, (string, string))> => {
  if !Node.existsSync(registryFile) {
    fail("repos/registry.toml does not exist")
  }
  switch Toml.parse(Node.readFileSync(registryFile)) {
  | Object(top) =>
    switch top->Dict.get("repos") {
    | Some(Object(table)) =>
      table
      ->Dict.toArray
      ->Array.map(((path, value)) =>
        switch value {
        | String(value) if remote->RegExp.test(value) && pathKey->RegExp.test(path) =>
          switch value->String.split(":") {
          | [user, repo] => (path, (user, repo))
          | _ => fail(`repos/registry.toml: ${path} = "${value}" is no user:repo`)
          }
        | _ => fail(`repos/registry.toml: ${path} is no path = "user:repo"`)
        }
      )
    | _ => fail("repos/registry.toml has no [repos] table")
    }
  | _ => fail("repos/registry.toml is not a table")
  }
}

let paths = () => registry()->Array.map(((path, _)) => path)

/** What mise.toml's [monorepo].config_roots names. */
let taskRoots = (): array<string> =>
  switch Toml.parse(Node.readFileSync(config)) {
  | Object(top) =>
    switch top->Dict.get("monorepo") {
    | Some(Object(monorepo)) =>
      switch monorepo->Dict.get("config_roots") {
      | Some(Array(roots)) =>
        roots->Array.filterMap(one =>
          switch one {
          | String(one) => Some(one)
          | _ => None
          }
        )
      | _ => []
      }
    | _ => []
    }
  | _ => []
  }

/** The workspace's own address, its origin as jj knows it, which a repository's `base` names. */
let origin = () =>
  Node.output(~cwd=root, "jj", ["git", "remote", "list"])
  ->String.split("\n")
  ->Array.findMap(line =>
    switch line->String.split(" ") {
    | ["origin", address] => Some(address)
    | _ => None
    }
  )

let isRepository = path =>
  Node.existsSync(Node.join([path, ".git"])) || Node.existsSync(Node.join([path, ".jj"]))

/** The workspace, or a repository by its path under repos/. */
let label = where =>
  where == root ? "workspace" : Node.relative(repos, where)->String.split(Node.sep)->Array.join("/")

/**
 * Every directory under repos/ that is a repository or holds none, a group walked through unnamed.
 */
let discovered = (): array<string> => {
  let found = []
  let rec holdsOne = at =>
    Node.entries(at)->Array.some(entry =>
      entry->Node.isDirectory && {
          let path = Node.join([at, entry->Node.name])
          isRepository(path) || holdsOne(path)
        }
    )
  let rec walk = at =>
    Node.entries(at)
    ->Array.filter(entry => entry->Node.isDirectory && !(entry->Node.name->String.startsWith(".")))
    ->Array.map(Node.name)
    ->Array.toSorted(String.compare)
    ->Array.forEach(name => {
      let path = Node.join([at, name])
      if isRepository(path) || !holdsOne(path) {
        found->Array.push(label(path))
      } else {
        walk(path)
      }
    })
  if Node.existsSync(repos) {
    walk(repos)
  }
  found
}

/**
 * The repositories a command applies to, the one named, every one with `--all`, or the workspace.
 */
let selected = (name: option<string>, ~everything=false): array<string> => {
  let listed = paths()
  switch (name, everything) {
  | (Some(name), true) =>
    fail(`${name} and --all ask for one repository and for every one; give one of them`)
  | (Some("workspace"), _) => [root]
  | (Some(name), _) =>
    if !(listed->Array.includes(name)) {
      fail(
        `repos/registry.toml does not list ${name}; the names are ${Array.concat(
            ["workspace"],
            listed,
          )->Array.join(", ")}`,
      )
    }
    let target = Node.join([repos, name])
    if !Node.existsSync(target) {
      fail(`repos/${name} is listed but not cloned -- \`mise run repos clone ${name}\` first`)
    }
    [target]
  | (None, false) => [root]
  | (None, true) =>
    Array.concat(
      [root],
      listed->Array.map(path => Node.join([repos, path]))->Array.filter(Node.existsSync),
    )
  }
}

/**
 * What a project carries that this workspace provides by position, a copy dead weight and a
 * difference a shadow. A link to the workspace's passes, as does an `.oxlintrc.json` extending it.
 */
let inherited = Layout.inherited

let extendsOf = /"extends"\s*:\s*\[\s*"([^"]+)"/

let extendsWorkspace = (path, provided) =>
  Node.basename(path) == ".oxlintrc.json" &&
    switch extendsOf->RegExp.exec(Node.readFileSync(path)) {
    | Some(result) =>
      switch result->RegExp.Result.matches {
      | [Some(named)] => Node.resolve([Node.dirname(path), named]) == Node.resolve([provided])
      | _ => false
      }
    | None => false
    }

/** Files a project keeps under version control that this workspace already provides by position. */
let shadowing = (project: string): array<string> =>
  Node.output(~cwd=project, "jj", ["file", "list"])
  ->String.split("\n")
  ->Array.filter(line => line != "")
  ->Array.filterMap(relative => {
    let path = Node.join([project, relative])
    let name = Node.basename(path)
    let provided = Node.join([root, name])
    let linked = try Node.lstatSync(path)->Node.statsIsSymbolicLink catch {
    | _ => false
    }
    let up = Node.relative(Node.dirname(path), provided)
    if !(inherited->Array.includes(name)) || relative->String.split("/")->Array.includes("vendor") {
      None
    } else if linked {
      let target = try Some(Node.realpathSync(path)) catch {
      | _ => None
      }
      target == Some(Node.realpathSync(provided))
        ? None
        : Some(`${relative} links elsewhere than the workspace's ${name}; link ${up}`)
    } else if !Node.existsSync(path) {
      None
    } else if Node.existsSync(provided) && Node.readFileSync(provided) == Node.readFileSync(path) {
      Some(`${relative} is a byte-identical copy of the workspace's; link ${up} instead`)
    } else if extendsWorkspace(path, provided) {
      None
    } else {
      Some(`${relative} shadows the workspace's, which is inherited by position`)
    }
  })

/** The registry, the task roots and the disk agree, and no project shadows what it inherits. */
let check = (): int => {
  let problems = ref(0)
  let say = line => {
    Console.log(line)
    problems := problems.contents + 1
  }
  let listed = paths()
  let roots = taskRoots()
  let expected = listed->Array.map(path => `repos/${path}`)
  expected->Array.forEach(one =>
    if !(roots->Array.includes(one)) {
      say(`mise.toml [monorepo].config_roots is missing ${one}`)
    }
  )
  roots->Array.forEach(one =>
    if !(expected->Array.includes(one)) {
      say(`mise.toml [monorepo].config_roots names ${one}, which repos/registry.toml does not list`)
    }
  )
  discovered()->Array.forEach(directory => {
    let path = Node.join([repos, directory])
    if !(listed->Array.includes(directory)) {
      say(`repos/${directory} is on disk but not listed in repos/registry.toml`)
    } else if !isRepository(path) {
      say(`repos/${directory} is not a repository -- repos/ is ignored, so nothing tracks it`)
    } else {
      shadowing(path)->Array.forEach(complaint => say(`repos/${directory}/${complaint}`))
    }
  })
  if problems.contents == 0 {
    Console.log(`${Int.toString(listed->Array.length)} listed, task roots agree`)
  }
  problems.contents > 0 ? 1 : 0
}
