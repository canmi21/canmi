/** What a landing owes every package of one repository, the same for the bump and the check. */
type row = {
  package: Packages.t,
  asked: Numbers.asked,
  /** Why it is owed a raise, the files or dependencies that changed. */
  because: array<string>,
}

type t = {
  packages: array<Packages.t>,
  rows: array<row>,
  /** What could not be read, where the patch is raised at least. */
  warnings: array<string>,
  /** What stops the repository being judged at all. */
  problems: array<string>,
}

/** Each interface's integer in a contracts.json, none where it does not parse. */
let integers = text =>
  switch Packages.parsed(text)->Option.flatMap(fields => fields->Dict.get("interfaces")) {
  | Some(Object(interfaces)) =>
    interfaces
    ->Dict.toArray
    ->Array.filterMap(((name, interface)) =>
      switch interface {
      | Object(fields) =>
        switch fields->Dict.get("version") {
        | Some(Number(version)) => Some((name, version->Float.toInt))
        | _ => None
        }
      | _ => None
      }
    )
    ->Dict.fromArray
  | _ => Dict.make()
  }

/** The commit `pin`'s text holds for a repository named `repository`, as an action's `ref` does. */
let pinned = (text, repository) =>
  Packages.group(
    RegExp.fromString(`ref: ([a-f0-9]{40}) # [^\\n]*${Node.basename(repository)}`),
    text,
  )

/** The contracts a state of this repository is built on, its own file or a sibling's at the pin. */
let contracts = (~root, ~read, versions: Project.versions) =>
  switch (versions.contracts, versions.repository, versions.pin) {
  | (None, _, _) => None
  | (Some(file), None, _) => read(file)
  | (Some(file), Some(repository), None) =>
    Landing.disk(~root=Node.resolve([root, repository]), file)
  | (Some(file), Some(repository), Some(pin)) =>
    read(pin)
    ->Option.flatMap(text => pinned(text, repository))
    ->Option.flatMap(commit =>
      Landing.siblingAt(~root=Node.resolve([root, repository]), ~commit, file)
    )
  }

/**
 * Who owes what, `changes` being each changed path with its text at the base and now. `minors`
 * names the packages a lander raises by judgment, by directory or name.
 */
let owing = (
  packages: array<Packages.t>,
  ~baseOf: Packages.t => option<Numbers.t>,
  ~changes: array<(string, option<string>, option<string>)>,
  ~versions: Project.versions,
  ~minors: array<string>,
  ~breaking: string => bool,
  ~before: option<Dict.t<int>>,
  ~after: option<Dict.t<int>>,
) => {
  let directories = packages->Array.map(package => package.directory)
  let real =
    changes
    ->Array.filter(((path, was, is)) =>
      was->Option.map(text => Counted.bare(path, text)) !=
        is->Option.map(text => Counted.bare(path, text))
    )
    ->Array.map(((path, _, _)) => path)
  let because = Dict.make()
  let note = (directory, why) =>
    because->Dict.set(directory, [...because->Dict.get(directory)->Option.getOr([]), why])
  real->Array.forEach(path => {
    if Counted.counts(path) {
      note(Counted.owner(directories, path), path)
    }
    let name = path->String.split("/")->Array.at(-1)
    let built = switch name {
    | Some("Cargo.lock") => Some(Packages.Cargo)
    | Some("pnpm-lock.yaml") => Some(Packages.Node)
    | _ => None
    }
    built->Option.forEach(kind => {
      let holder = Counted.owner(directories, path)
      packages
      ->Array.filter(
        package =>
          package.builds->Array.includes(kind) &&
          package.directory != holder &&
          Counted.under(package.directory, holder),
      )
      ->Array.forEach(package => note(package.directory, path))
    })
    versions.counts
    ->Dict.toArray
    ->Array.forEach(((directory, declared)) =>
      if declared->Array.some(item => Counted.under(path, item)) {
        note(directory, path)
      }
    )
  })
  let own = because->Dict.keysToArray
  let rose = name =>
    switch (before, after) {
    | (Some(before), Some(after)) =>
      after->Dict.get(name)->Option.getOr(0) > before->Dict.get(name)->Option.getOr(0)
    | _ => false
    }
  packages->Array.forEach(package =>
    versions.serves
    ->Dict.get(package.directory)
    ->Option.getOr([])
    ->Array.filter(rose)
    ->Array.forEach(name => note(package.directory, `interface ${name} rose`))
  )
  // A package's dependency is among what it is built from, the repository's root reaching none.
  let rec spread = () => {
    let grown =
      packages->Array.filter(package =>
        package.directory != "" &&
        because->Dict.get(package.directory)->Option.isNone &&
        Packages.uses(packages, package)->Array.some(used => because->Dict.get(used)->Option.isSome)
      )
    grown->Array.forEach(package =>
      Packages.uses(packages, package)
      ->Array.filter(used => because->Dict.get(used)->Option.isSome)
      ->Array.forEach(used => note(package.directory, `depends on ${used}`))
    )
    if grown != [] {
      spread()
    }
  }
  spread()
  packages->Array.map(package => {
    let served = versions.serves->Dict.get(package.directory)->Option.getOr([])
    let target = switch served {
    | [one] => after->Option.flatMap(after => after->Dict.get(one))
    | _ => None
    }
    let named = [package.directory, package.name]->Array.some(name => minors->Array.includes(name))
    let severalRose = served->Array.length > 1 && served->Array.some(rose)
    {
      package,
      because: because->Dict.get(package.directory)->Option.getOr([]),
      asked: {
        base: baseOf(package),
        now: package.version,
        changed: because->Dict.get(package.directory)->Option.isSome,
        target,
        minor: named ||
        severalRose ||
        (own->Array.includes(package.directory) && breaking(package.directory)),
      },
    }
  })
}

/** The whole of one repository, read from its working copy and the main line beneath it. */
let judged = (~root, ~minors=[], ~at=?) => {
  let versions = Project.versionsAt(root)
  let top = at->Option.getOr("@")
  let current = path =>
    switch at {
    | Some(commit) => Landing.at(~root, ~base=commit, path)
    | None => Landing.disk(~root, path)
    }
  let beneath = switch at {
  | Some(commit) => Landing.firstParent(~root, commit)
  | None => Landing.base(~root)
  }
  switch beneath {
  | None => {packages: [], rows: [], warnings: [], problems: ["no main line beneath it"]}
  | Some(base) =>
    let tracked = Landing.tracked(~root, ~top)
    let (packages, problems) = Packages.found(~fallback=Node.basename(root), ~read=current, tracked)
    let changes =
      Landing.changed(~root, ~base, ~top)->Array.map(path => (
        path,
        Landing.at(~root, ~base, path),
        current(path),
      ))
    let changedPaths = changes->Array.map(((path, _, _)) => path)
    let baseOf = (package: Packages.t) => {
      let moved = package.manifests->Array.filter(({path}) => changedPaths->Array.includes(path))
      if moved == [] {
        Some(package.version)
      } else {
        // A manifest absent at the base, of a package holding no other, is a new package.
        let was =
          package.manifests->Array.filterMap(({path, kind}) =>
            Landing.at(~root, ~base, path)->Option.map(text => {Packages.path, kind, text})
          )
        was == []
          ? None
          : was
            ->Array.filterMap(manifest =>
              Packages.versionOf(manifest)->Result.mapOr(None, v => Some(v))
            )
            ->Array.reduce(Numbers.zero, (best, v) => Numbers.later(v, best) ? v : best)
            ->Some
      }
    }
    let serving = versions.serves->Dict.valuesToArray->Array.flat != []
    let read = state => contracts(~root, ~read=state, versions)
    let after = serving ? read(current)->Option.map(integers) : None
    let before = serving ? read(path => Landing.at(~root, ~base, path))->Option.map(integers) : None
    let warnings =
      serving && (after->Option.isNone || before->Option.isNone)
        ? ["the served interfaces could not be read at both ends, so the patch is raised at least"]
        : []
    let breakingMessages =
      Landing.messages(~root, ~base, ~top, "")->Array.some(Landing.breaking)
        ? directory => Landing.messages(~root, ~base, ~top, directory)->Array.some(Landing.breaking)
        : _ => false
    {
      packages,
      problems: [
        ...problems,
        ...minors->Array.filterMap(name => {
          switch packages->Array.find(package =>
            package.name == name || package.directory == name
          ) {
          | None => Some(`--minor ${name} matches no package`)
          | Some(package) =>
            versions.serves->Dict.get(package.directory)->Option.getOr([])->Array.length == 1
              ? Some(`--minor ${name} serves one interface, which sets its minor`)
              : None
          }
        }),
      ],
      warnings,
      rows: owing(
        packages,
        ~baseOf,
        ~changes,
        ~versions,
        ~minors,
        ~breaking=breakingMessages,
        ~before,
        ~after,
      ),
    }
  }
}

/** The crates a repository holds, each with its version. */
let crates = (packages: array<Packages.t>, ~version: Packages.t => Numbers.t) =>
  packages->Array.filterMap(package =>
    package.manifests->Array.some(({kind}) => kind == Cargo)
      ? Some((package.name, version(package)))
      : None
  )

type debt = {wanted: Numbers.t, commit: string}

/** The unpaid version after each outgoing landing, kept until its full amount is reached. */
let replay = (states: array<(string, t)>) => {
  let owed = Dict.make()
  states->Array.forEach(((commit, state)) => {
    state.rows->Array.forEach(row => {
      let name = row.package.name
      let wanted = Numbers.owed(row.asked)
      let previous = owed->Dict.get(name)
      if (
        Numbers.later(wanted, row.asked.now) &&
        previous->Option.mapOr(true, debt => Numbers.later(wanted, debt.wanted))
      ) {
        owed->Dict.set(name, {wanted, commit})
      }
      owed
      ->Dict.get(name)
      ->Option.forEach(
        debt => {
          if !Numbers.later(debt.wanted, row.asked.now) {
            owed->Dict.delete(name)
          }
        },
      )
    })
  })
  let names =
    states->Array.at(-1)->Option.mapOr([], ((_, state)) => state.packages->Array.map(p => p.name))
  owed
  ->Dict.keysToArray
  ->Array.forEach(name => {
    if !(names->Array.includes(name)) {
      owed->Dict.delete(name)
    }
  })
  owed
}

let outgoing = (~root) =>
  Landing.outgoing(~root)->Array.map(commit => (commit, judged(~root, ~at=commit)))

/** The current landing together with what the outgoing main line still owes. */
let planned = (~root, ~minors=[]) => {
  let current = judged(~root, ~minors)
  let owed = replay(outgoing(~root))
  {
    ...current,
    rows: current.rows->Array.map(row => {
      switch owed->Dict.get(row.package.name) {
      | Some(debt) if Numbers.later(debt.wanted, Numbers.rolled(row.asked)) => {
          ...row,
          asked: {...row.asked, base: Some(debt.wanted), changed: false, minor: false},
          because: [...row.because, "outgoing landing"],
        }
      | _ => row
      }
    }),
  }
}

/** The sibling crates reached by path, read at the commit this state pins. */
let siblingVersions = (~root, ~read, packages: array<Packages.t>) => {
  let versions = Project.versionsAt(root)
  switch (versions.repository, versions.pin) {
  | (Some(repository), Some(pin)) =>
    let sibling = Node.resolve([root, repository])
    let commit = read(pin)->Option.flatMap(text => pinned(text, repository))
    if !Registry.isRepository(sibling) {
      Ok([])
    } else {
      switch commit {
      | None => Error(`${pin} pins no commit of ${repository}`)
      | Some(commit) =>
        let present =
          Landing.git(~root=sibling, ["cat-file", "-e", `${commit}^{commit}`])->Option.isSome
        if !present {
          Error(`${repository} cannot be read at ${commit}, the commit ${pin} pins`)
        } else {
          let read = path =>
            path->String.startsWith(sibling ++ "/")
              ? Landing.siblingAt(~root=sibling, ~commit, Node.relative(sibling, path))
              : read(Node.relative(root, path))
          Ok(
            Packages.siblingCrates(
              ~root,
              ~sibling,
              ~read,
              packages->Array.map(package => package.directory),
            )->Array.filterMap(directory => {
              read(Node.join([sibling, directory, "Cargo.toml"]))->Option.flatMap(text => {
                let manifest = {Packages.path: directory ++ "/Cargo.toml", kind: Cargo, text}
                switch (Packages.nameOf(manifest), Packages.versionOf(manifest)) {
                | (Some(name), Ok(version)) => Some((name, version))
                | _ => None
                }
              })
            }),
          )
        }
      }
    }
  | _ => Ok([])
  }
}
