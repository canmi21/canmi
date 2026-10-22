/**
 * The id spaces and the RFCs each holds, read from every cloned repository whose workspace.toml
 * names its space in `[rfcs] ids`, and from the workspace's own docs/rfcs for `workspace`.
 */
type file = {
  ...Rfc_name.t,
  space: string,
  /** The repository holding it, `workspace` or its path under repos/. */
  repo: string,
  area: string,
  path: string,
  /** Its path from the workspace's root, as a problem names it. */
  where: string,
}

/** What a space's repositories hold, its RFCs and the paths of whatever else is in docs/rfcs. */
type read = {files: array<file>, strays: array<string>, areas: array<string>}

let root = Registry.root

let checkout = repo => repo == Planning.workspaceSpace ? root : Node.join([Registry.repos, repo])

/** Each repository by its label and the id space it declares, the workspace's first. */
let declared = (): array<(string, string)> =>
  Array.concat(
    [(Planning.workspaceSpace, Planning.workspaceSpace)],
    Registry.paths()->Array.filterMap(path =>
      switch Project.read(Node.join([Registry.repos, path])) {
      | Ok({rfcs: Some({ids})}) => Some((path, ids))
      | _ => None
      }
    ),
  )

/** The id space `repo` declares, if any. */
let spaceOf = repo =>
  declared()->Array.findMap(((label, space)) => label == repo ? Some(space) : None)

/** Every space declared, each once, the workspace's first. */
let names = () =>
  declared()->Array.reduce([], (seen, (_, space)) =>
    seen->Array.includes(space) ? seen : Array.concat(seen, [space])
  )

let relative = path => Node.relative(root, path)->String.split(Node.sep)->Array.join("/")

/** One repository's docs/rfcs, each area one level of directories. */
let inRepository = (~space, ~repo): read => {
  let directory = Node.join([checkout(repo), Planning.rfcDirectory])
  let files = []
  let strays = []
  let areas = []
  if Node.existsSync(directory) {
    Node.entries(directory)
    ->Array.toSorted((a, b) => String.compare(a->Node.name, b->Node.name))
    ->Array.forEach(entry => {
      let area = entry->Node.name
      let folder = Node.join([directory, area])
      if area->String.startsWith(".") {
        ()
      } else if !(entry->Node.isDirectory) {
        strays->Array.push(folder)
      } else {
        areas->Array.push(area)
        Node.entries(folder)
        ->Array.toSorted((a, b) => String.compare(a->Node.name, b->Node.name))
        ->Array.forEach(inside => {
          let path = Node.join([folder, inside->Node.name])
          switch inside->Node.isFile ? Rfc_name.parse(inside->Node.name) : None {
          | Some({day, order, slug, id}) =>
            files->Array.push({
              day,
              order,
              slug,
              id,
              space,
              repo,
              area,
              path,
              where: relative(path),
            })
          | None => strays->Array.push(path)
          }
        })
      }
    })
  }
  {files, strays, areas}
}

/** Every cloned repository's part of `space`, those not cloned passed over. */
let read = (space): read => {
  let parts =
    declared()
    ->Array.filter(((repo, named)) => named == space && Node.existsSync(checkout(repo)))
    ->Array.map(((repo, _)) => inRepository(~space, ~repo))
  {
    files: parts->Array.flatMap(part => part.files),
    strays: parts->Array.flatMap(part => part.strays),
    areas: parts->Array.flatMap(part => part.areas),
  }
}
