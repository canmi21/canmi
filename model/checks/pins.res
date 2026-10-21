/** Each [tools] pin against model/rules/toolchain.res, a major or a reason beside it. */
let entry = /^\s*([\w:@\/.-]+)\s*=\s*"([^"]*)"\s*(#.*)?$/
let table = /^\s*\[([^\]]+)\]\s*$/

let main = (~root): array<string> => {
  let inside = ref(false)
  References.read(Node.join([root, "mise.toml"]))
  ->String.split("\n")
  ->Array.filterMap(line => {
    switch table->RegExp.exec(line) {
    | Some(result) =>
      inside := result->RegExp.Result.matches == [Some("tools")]
      None
    | None if inside.contents =>
      switch entry->RegExp.exec(line) {
      | Some(result) =>
        switch result->RegExp.Result.matches {
        | [Some(tool), Some(version), None] if !(Toolchain.pin->RegExp.test(version)) =>
          Some(`mise.toml: ${tool} = "${version}" is narrower than a major and says nothing of why`)
        | _ => None
        }
      | None => None
      }
    | None => None
    }
  })
}
