/**
 * `rfc new <name> [<area>] [--in <path>] [--status S] [--day yyyy-mmdd] [--dry-run]`, an RFC
 * started from its name, its slug and id drawn so nobody picks them. It stands flat in docs/rfcs
 * while the repository holds at most `Layout.widest`, and in an area of its own tree past that.
 * RFC 2ut6h.
 */
let usage = () => {
  Console.error(
    "usage: mise run rfc new <name> [<area>] [--in <path>] [--status S] [--day yyyy-mmdd] [--dry-run]",
  )
  Console.error(
    "  the name in title case, at most 32 characters; the area a directory of the repository's",
  )
  Console.error(
    `  own tree, given once it holds more than ${Int.toString(
        Layout.widest,
      )} RFCs and never before;`,
  )
  Console.error(
    "  --in a repository repos/registry.toml lists that declares [rfcs], the workspace's",
  )
  Console.error(
    `  own unless given; the status one of ${Planning.newStatuses->Array.join(", ")}, draft`,
  )
  Console.error(`  unless given; e.g. mise run rfc new "Hue Pairs" libs --in monoflake/platform`)
  Node.exit(2)
}

/** The value after `flag`, taken out of `args` with it. */
let option = (args: array<string>, flag) =>
  switch args->Array.indexOf(flag) {
  | -1 => None
  | at =>
    let value = switch args->Array.get(at + 1) {
    | Some(value) if !(value->String.startsWith("--")) => value
    | _ => usage()
    }
    args->Array.splice(~start=at, ~remove=2, ~insert=[])
    Some(value)
  }

/** `text` quoted as oxfmt quotes a YAML string, in single quotes unless it holds more of them. */
let quoted = text => {
  let count = mark => text->String.split(mark)->Array.length - 1
  count("'") > count("\"")
    ? JSON.stringifyAny(text)->Option.getOr("\"\"")
    : `'${text->String.replaceAll("'", "''")}'`
}

/** What a new RFC holds before anything is written in it. */
let skeleton = (~name, ~status) =>
  `---
name: ${quoted(name)}
title:
status: ${status}
supersedes: []
references: []
---

## Question

## Options
${status == "draft" ? "" : "\n## Decision\n"}`

/**
 * Where an RFC goes among a repository's `count`: `Ok("")` flat, `Ok(area)` in an area of its tree,
 * or why it can go nowhere.
 */
let placement = (~repo, ~count, ~area: option<string>, ~inTree: string => bool) => {
  let widest = Int.toString(Layout.widest)
  switch (count > Layout.widest, area) {
  | (false, Some(_)) =>
    Error(
      `${repo} holds ${Int.toString(
          count,
        )} RFCs, at most ${widest}, so they stand flat: give no area`,
    )
  | (false, None) if count == Layout.widest =>
    Error(
      `${repo} holds ${widest} RFCs, the most that stand flat: split them into areas of its tree first`,
    )
  | (false, None) => Ok("")
  | (true, None) =>
    Error(`${repo} holds more than ${widest} RFCs, so a new one needs an area of its tree`)
  | (true, Some(area)) if !(Rfc_name.area->RegExp.test(area)) =>
    Error(`${area} is not lowercase words and hyphens`)
  | (true, Some(area)) if !inTree(area) => Error(`${area} is no directory of ${repo}'s own tree`)
  | (true, Some(area)) => Ok(area)
  }
}

let main = () => {
  let given = Node.args()
  if given[0] != Some("new") {
    usage()
  }
  let args = given->Array.slice(~start=1)
  let into = option(args, "--in")->Option.getOr(Planning.workspaceSpace)
  let status = option(args, "--status")->Option.getOr("draft")
  let day = option(args, "--day")->Option.getOr(Rfc_name.today())
  let dry = args->Array.includes("--dry-run")
  let (name, area) = switch args->Array.filter(arg => !(arg->String.startsWith("--"))) {
  | [name] => (name->String.trim, None)
  | [name, area] => (name->String.trim, Some(area))
  | _ => usage()
  }
  if name->String.length > 32 {
    Console.error(
      `the name holds ${Int.toString(name->String.length)} characters, more than the 32 allowed`,
    )
    usage()
  }
  let slug = Rfc_name.slugOf(name)
  if (
    !(Rfc_name.slug->RegExp.test(slug)) ||
    !(Planning.newStatuses->Array.includes(status)) ||
    Rfc_name.parse(`${day}-a-aaaaa.md`) == None
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
  let count = files->Array.filter(file => file.repo == into)->Array.length
  let inside = switch placement(~repo=into, ~count, ~area, ~inTree=area =>
    Rfc_spaces.tree(into)->Array.includes(area)
  ) {
  | Ok(inside) => inside
  | Error(says) =>
    Console.error(says)
    Node.exit(2)
  }
  if ids->Array.includes(inside) {
    Console.error(`${inside} is an RFC's id in ${space}, so it cannot name an area`)
    Node.exit(2)
  }
  // An area's name is kept from the ids, since an id stands where an area's name does in a path.
  let id = Rfc_name.fresh(Array.concat(ids, areas))
  let directory = Node.join(
    inside == ""
      ? [Rfc_spaces.checkout(into), Planning.rfcDirectory]
      : [Rfc_spaces.checkout(into), Planning.rfcDirectory, inside],
  )
  let path = Node.join([directory, Rfc_name.format({day, slug, id})])
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
