/** A sibling checkout follows the calling repository's pin where it declares one. */
let reference = (~root, ~sibling) => {
  let versions = Project.versionsAt(root)
  switch (versions.repository, versions.pin) {
  | (Some(repository), Some(pin)) if Node.resolve([root, repository]) == Node.resolve([sibling]) =>
    switch Landing.disk(~root, pin)->Option.flatMap(text => Roll.pinned(text, repository)) {
    | Some(commit) => commit
    | None => Registry.fail(`${pin} pins no commit of ${repository}`)
    }
  | _ => "main"
  }
}

if Node.isMain {
  switch Node.args() {
  | [root, sibling] => Console.log(reference(~root, ~sibling))
  | _ => Registry.fail("beside <calling repository> <sibling>")
  }
}
