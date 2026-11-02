/** The custom-domains rule, docs/toolchain/runtime.md, over every wrangler file. */
let named = /(^|\/)wrangler\.(jsonc?|toml)$/

/** A test's fixtures are no deployment, so they are passed over. */
let fixture = path =>
  path->String.split("/")->Array.some(part => part == "tests" || part == "fixtures")

/** JSON with whole-line comments and trailing commas, as wrangler.jsonc allows. */
let plain = text =>
  text->String.replaceRegExp(/^\s*\/\/.*$/gm, "")->String.replaceRegExp(/,(\s*[}\]])/g, "$1")

let read = (text, ~file) =>
  file->String.endsWith(".toml") ? Toml.parse(text) : JSON.parseOrThrow(plain(text))

let flags = ["workers_dev", "preview_urls"]

/** The flags a configuration leaves on, an absent top level meaning on, an env only by name. */
let problems = (config: JSON.t, ~file): array<string> => {
  let top = config->JSON.Decode.object->Option.getOr(Dict.make())
  let on =
    flags->Array.filterMap(flag =>
      top->Dict.get(flag) == Some(Boolean(false)) ? None : Some(`${file}: ${flag} is not false`)
    )
  let environments =
    top->Dict.get("env")->Option.flatMap(JSON.Decode.object)->Option.getOr(Dict.make())
  let inner =
    environments
    ->Dict.toArray
    ->Array.flatMap(((name, env)) =>
      flags->Array.filterMap(flag =>
        env->JSON.Decode.object->Option.flatMap(fields => fields->Dict.get(flag)) ==
          Some(Boolean(true))
          ? Some(`${file}: env ${name} turns ${flag} on`)
          : None
      )
    )
  Array.concat(on, inner)
}

let main = (~root): array<string> =>
  Lines.tracked(root)
  ->Array.filter(path => named->RegExp.test(path) && !fixture(path))
  ->Array.flatMap(path =>
    try problems(read(Node.readFileSync(Node.join([root, path])), ~file=path), ~file=path) catch {
    | JsExn(_) => [`${path}: cannot be read`]
    }
  )
