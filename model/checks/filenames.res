/** Every name the workspace tracks against model/rules/naming.res; no CLAUDE.md anywhere. */
let fits = (segment, ~file) => {
  let bare = segment->String.startsWith(".") ? segment->String.slice(~start=1) : segment
  let underscored = file && Naming.underscored->Array.some(suffix => bare->String.endsWith(suffix))
  Naming.assigned->Array.includes(segment) ||
    Naming.shape->RegExp.test(underscored ? bare->String.replaceAll("_", "-") : bare)
}

/** Every name `root` tracks that breaks the naming rule. */
let names = (~root): array<string> =>
  References.tracked(root)
  ->Array.map(path => Node.relative(root, path))
  ->Array.filter(relative => !Layout.vendored(relative))
  ->Array.filterMap(relative => {
    let segments = relative->String.split("/")
    let last = segments->Array.length - 1
    segments
    ->Array.mapWithIndex((segment, at) => (segment, at == last))
    ->Array.find(((segment, file)) => !fits(segment, ~file))
    ->Option.map(((segment, _)) => `${relative}: ${segment} breaks the naming rule`)
  })

let main = (~root): array<string> => {
  let refused =
    [root]
    ->Array.concat(
      Waiting.active()
      ->Array.map(path => Node.join([Registry.repos, path]))
      ->Array.filter(Node.existsSync),
    )
    ->Array.flatMap(repository =>
      References.tracked(repository)
      ->Array.map(path => Node.relative(repository, path))
      ->Array.filter(line => Naming.refused->Array.includes(Node.basename(line)))
      ->Array.map(line => `${Node.relative(root, Node.join([repository, line]))} is refused`)
    )
  Array.concat(names(~root), refused)
}
