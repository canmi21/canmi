/** The constants a spec takes from the model, run once and written into its configurations. */
type value = Int(int) | Bool(bool) | Text(string) | Ints(array<int>) | Texts(array<string>)

let refuse = (spec, what) => throw(Protocol_manifest.Refused(`${spec} constants: ${what}`))

let isName = name => /^[A-Za-z_][A-Za-z0-9_]*$/->RegExp.test(name)

let quoted = text => JSON.stringifyAny(text)->Option.getOr("\"\"")

let render = value =>
  switch value {
  | Int(n) => Int.toString(n)
  | Bool(flag) => flag ? "TRUE" : "FALSE"
  | Text(text) => quoted(text)
  | Ints(items) => `{${items->Array.map(n => Int.toString(n))->Array.join(", ")}}`
  | Texts(items) => `{${items->Array.map(quoted)->Array.join(", ")}}`
  }

let valueOf = (spec, name, json) => {
  let whole = number => Float.toInt(number)->Int.toFloat == number
  switch json {
  | JSON.Number(number) if whole(number) => Int(Float.toInt(number))
  | Boolean(flag) => Bool(flag)
  | String(text) => Text(text)
  | Array(items) =>
    switch (
      items->Array.every(item => item->JSON.Decode.float->Option.mapOr(false, whole)),
      items->Array.every(item => item->JSON.Decode.string != None),
    ) {
    | (true, _) =>
      Ints(items->Array.filterMap(item => item->JSON.Decode.float->Option.map(Float.toInt)))
    | (_, true) => Texts(items->Array.filterMap(JSON.Decode.string))
    | _ => refuse(spec, `${name} must be an array of integers or of strings`)
    }
  | _ => refuse(spec, `${name} must be an integer, a boolean, a string or an array of them`)
  }
}

/** A command's stdout as the values it names, in the order it gives them. */
let parse = (~spec, out) =>
  switch JSON.parseOrThrow(out) {
  | Object(fields) =>
    fields
    ->Dict.toArray
    ->Array.map(((name, json)) => {
      if !isName(name) {
        refuse(spec, `${name} is no constant name`)
      }
      (name, valueOf(spec, name, json))
    })
  | _ => refuse(spec, "the command must print one JSON object")
  | exception _ => refuse(spec, "the command did not print JSON")
  }

/** The configuration with the line of each named constant replaced, a name it lacks refused. */
let apply = (~spec, config, values) =>
  values->Array.reduce(config, (config, (name, value)) => {
    let line = RegExp.fromString(`^([ \\t]*(?:CONSTANTS?[ \\t]+)?)${name}[ \\t]*=.*$`, ~flags="m")
    if !(line->RegExp.test(config)) {
      refuse(spec, `${name} is no constant the configuration declares`)
    }
    let text = render(value)->String.replaceAll("$", "$$$$")
    config->String.replaceRegExp(line, `$1${name} = ${text}`)
  })

/** The command run from the repository root, its values, or a refusal where it fails. */
let run = (~spec, ~root, command: array<string>) => {
  let ran = Node.spawnSync(
    command->Array.getUnsafe(0),
    command->Array.slice(~start=1),
    {cwd: root, encoding: "utf8", maxBuffer: 268435456},
  )
  switch ran.status->Nullable.getOr(1) {
  | 0 => parse(~spec, ran.stdout->Nullable.getOr(""))
  | status =>
    refuse(
      spec,
      `${command->Array.join(" ")} exited ${Int.toString(status)}\n${ran.stderr->Nullable.getOr(
          "",
        )}`,
    )
  }
}
