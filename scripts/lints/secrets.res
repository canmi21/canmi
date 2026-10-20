/**
 * The gate refusing a plaintext secrets file: each file `.sops.yaml` claims carries a `sops` block
 * and `ENC[` on every value. A repository's `secrets`, from its root; docs/toolchain.md.
 */
let pathRegex = /path_regex:\s*(\S+)/g

/** `path_regex` entries from `.sops.yaml`, read without a YAML dependency. */
let guardedPatterns = root => {
  let rules = Node.join([root, ".sops.yaml"])
  if !Node.existsSync(rules) {
    []
  } else {
    let text = Node.readFileSync(rules)
    let found = []
    pathRegex->RegExp.setLastIndex(0)
    let rec next = () =>
      switch pathRegex->RegExp.exec(text) {
      | Some(result) =>
        switch result->RegExp.Result.matches {
        | [Some(pattern)] => found->Array.push(RegExp.fromString(pattern))
        | _ => ()
        }
        next()
      | None => ()
      }
    next()
    found
  }
}

/** Why `text`, a file sops should have written, is not safe to commit, or None if it is. */
let unencrypted = (text: string): option<string> =>
  switch JSON.parseOrThrow(text) {
  | Object(data) if data->Dict.get("sops")->Option.isSome =>
    let bare =
      data
      ->Dict.toArray
      ->Array.filterMap(((key, value)) =>
        switch value {
        | String(value) if key != "sops" && !(value->String.startsWith("ENC[")) => Some(key)
        | _ => None
        }
      )
      ->Array.toSorted(String.compare)
    bare->Array.length > 0 ? Some(`values are not encrypted: ${bare->Array.join(", ")}`) : None
  | _ => Some("no sops block: this is plaintext")
  | exception _ =>
    Some("not readable as JSON, so it is neither valid plaintext nor valid sops output")
  }

/** Pruned while walking, so a build writing and removing its scratch files is never walked. */
let skipped = ["node_modules", ".jj", ".git", "target"]

/** Every file under `root` but those under a skipped directory, relative to it, `/` between. */
let walk = root => {
  let found = []
  let rec visit = directory =>
    Node.entries(directory)->Array.forEach(entry => {
      let path = Node.join([directory, entry->Node.name])
      if entry->Node.isDirectory {
        if !(skipped->Array.includes(entry->Node.name)) {
          visit(path)
        }
      } else if (
        entry->Node.isFile ||
          (entry->Node.isSymbolicLink &&
            Node.stat(path)->Option.mapOr(false, stats => stats->Node.statsIsFile))
      ) {
        found->Array.push(Node.relative(root, path)->String.split(Node.sep)->Array.join("/"))
      }
    })
  visit(root)
  found
}

/** The gate: each guarded file encrypted, or every one that is not, by why. */
let main = (~root=Node.cwd()) => {
  let patterns = guardedPatterns(root)
  if patterns->Array.length == 0 {
    Console.log("no .sops.yaml rules to enforce")
  } else {
    let problems = []
    let checked = ref(0)
    walk(root)->Array.forEach(path =>
      if patterns->Array.some(pattern => pattern->RegExp.test(path)) {
        checked := checked.contents + 1
        let text = try Node.readFileSync(Node.join([root, path])) catch {
        | _ => ""
        }
        switch unencrypted(text) {
        | Some(why) => problems->Array.push(`${path}: ${why}`)
        | None => ()
        }
      }
    )
    if problems->Array.length > 0 {
      Console.error("Plaintext secrets found:\n")
      problems->Array.forEach(problem => Console.error(`  ${problem}`))
      Console.error(
        "\nEncrypt with `sops encrypt -i <file>` before committing. If a real credential was ever " ++ "written here in plaintext, rotate it -- removing the file does not remove it from history.",
      )
      Node.exit(1)
    }
    Console.log(`secrets OK: ${Int.toString(checked.contents)} file(s) encrypted`)
  }
}

if Node.isMain {
  main()
}
