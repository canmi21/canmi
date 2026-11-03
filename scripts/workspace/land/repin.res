let repinned = (text, ~repository, ~commit) => {
  let replaced = ref(false)
  text
  ->String.split("\n")
  ->Array.map(line => {
    switch Roll.pinned(line, repository) {
    | Some(previous) if !replaced.contents =>
      replaced := true
      line->String.replace(`ref: ${previous}`, `ref: ${commit}`)
    | _ => line
    }
  })
  ->Array.join("\n")
}

let moved = (~root) => {
  let versions = Project.versionsAt(root)
  switch (versions.repository, versions.pin) {
  | (Some(repository), Some(pin)) =>
    let text = Landing.disk(~root, pin)
    switch text->Option.flatMap(text => Roll.pinned(text, repository)) {
    | None => Error(`${pin} pins no commit of ${repository}`)
    | Some(from) =>
      let sibling = Node.resolve([root, repository])
      switch Onset.read(
        ~root=sibling,
        ["log", "-r", "main@origin", "--no-graph", "-T", "commit_id"],
      ) {
      | None => Error(`${repository} cannot be read at main@origin`)
      | Some(to) if !RegExp.test(/^[a-f0-9]{40}$/, to) =>
        Error(`${repository} cannot be read at main@origin`)
      | Some(to) if to == from => Ok(None)
      | Some(to) =>
        Node.writeFileSync(
          Node.join([root, pin]),
          repinned(text->Option.getOr(""), ~repository, ~commit=to),
        )
        Ok(Some((from, to, pin)))
      }
    }
  | _ => Ok(None)
  }
}
