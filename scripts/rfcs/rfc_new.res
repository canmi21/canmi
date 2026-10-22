/**
 * `new-rfc <name> <area> [--in <path>] [--status S] [--day yyyy-mmdd] [--dry-run]`, an RFC started
 * from its name, its slug, id and place in the day drawn so nobody picks them. RFC 2ut6h.
 */
let usage = () => {
  Console.error(
    "usage: mise run new-rfc <name> <area> [--in <path>] [--status S] [--day yyyy-mmdd] [--dry-run]",
  )
  Console.error(
    "  the name in title case, at most 32 characters; the area a directory of docs/rfcs;",
  )
  Console.error(
    "  --in a repository repos/registry.toml lists that declares [rfcs], the workspace's",
  )
  Console.error(
    `  own unless given; the status one of ${Planning.statuses->Array.join(", ")}, draft`,
  )
  Console.error(`  unless given; e.g. mise run new-rfc "Hue Pairs" design --in monoflake/platform`)
  Node.exit(2)
}

/** The value after `flag`, taken out of `args` with it. */
let option = (args: array<string>, flag) =>
  switch args->Array.indexOf(flag) {
  | -1 => None
  | at =>
    let value = args->Array.get(at + 1)
    args->Array.splice(~start=at, ~remove=2, ~insert=[])
    value
  }

/** What a new RFC holds before anything is written in it. */
let skeleton = (~name, ~status) =>
  `---
name: ${JSON.stringifyAny(name)->Option.getOr("")}
title:
status: ${status}
supersedes: []
blocked-by: []
commits: []
references: []
---

## Question
${status == "draft" ? "" : "\n## Decision\n"}`

let main = () => {
  let args = Node.args()
  let into = option(args, "--in")->Option.getOr(Planning.workspaceSpace)
  let status = option(args, "--status")->Option.getOr("draft")
  let day = option(args, "--day")->Option.getOr(Rfc_name.today())
  let dry = args->Array.includes("--dry-run")
  let (name, area) = switch args->Array.filter(arg => !(arg->String.startsWith("--"))) {
  | [name, area] => (name->String.trim, area)
  | _ => usage()
  }
  let slug = Rfc_name.slugOf(name)
  if (
    !(Rfc_name.area->RegExp.test(area)) ||
    !(Rfc_name.slug->RegExp.test(slug)) ||
    name->String.length > 32 ||
    !(Planning.statuses->Array.includes(status)) ||
    Rfc_name.parse(`${day}-01-a-aaaaa.md`) == None
  ) {
    usage()
  }
  let space = switch Rfc_spaces.spaceOf(into) {
  | Some(space) => space
  | None =>
    Console.error(`${into} is no repository that declares [rfcs] in its workspace.toml`)
    Node.exit(2)
  }
  let {files, areas}: Rfc_spaces.read = Rfc_spaces.read(space)
  let ids = files->Array.map(file => file.id)
  if ids->Array.includes(area) {
    Console.error(`${area} is an RFC's id in ${space}, so it cannot name an area`)
    Node.exit(2)
  }
  let order =
    files->Array.reduce(0, (most, file) =>
      file.day == day ? Math.Int.max(most, file.order) : most
    ) + 1
  if order > 99 {
    Console.error(`${day} holds 99 RFCs in ${space} already, the most two digits can place`)
    Node.exit(1)
  }
  // An area's name is kept from the ids, since an id stands where an area's name does in a path.
  let id = Rfc_name.fresh(Array.concat(ids, areas))
  let directory = Node.join([Rfc_spaces.checkout(into), Planning.rfcDirectory, area])
  let path = Node.join([directory, Rfc_name.format({day, order, slug, id})])
  if dry {
    Console.log(`would write ${Rfc_spaces.relative(path)}`)
  } else {
    Node.mkdirAll(directory)
    Node.writeFileSync(path, skeleton(~name, ~status))
    Console.log(Rfc_spaces.relative(path))
  }
  Console.log(`id ${id} in ${space}, cited as RFC ${id}`)
}

if Node.isMain {
  main()
}
