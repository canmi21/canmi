type fixture = {rule: string, source: string}

let fixtures = [{rule: "no-irregular-whitespace", source: "const value\u00a0= 1;\n"}]

type tools = {
  format: string => result<string, string>,
  lint: (string, string) => result<int, string>,
}

let measured = (fixture, tools) => {
  let fail = why => [`${fixture.rule}: ${why}`]
  switch tools.lint(fixture.rule, fixture.source) {
  | Error(why) => fail(`linter failed before formatting ${why}`)
  | Ok(0) => fail("fixture does not violate the rule")
  | Ok(_) =>
    switch tools.format(fixture.source) {
    | Error(why) => fail(`formatter failed ${why}`)
    | Ok(formatted) =>
      switch tools.lint(fixture.rule, formatted) {
      | Error(why) => fail(`linter failed after formatting ${why}`)
      | Ok(0) => []
      | Ok(_) => fail("formatter leaves the violation")
      }
    }
  }
}

let held = (~rules=Format.overlapping, ~samples=fixtures, tools) => {
  let missing = rules->Array.flatMap(rule => {
    let matching = samples->Array.filter(fixture => fixture.rule == rule)
    switch matching {
    | [] => [`${rule}: no overlap fixture`]
    | [fixture] => measured(fixture, tools)
    | _ => [`${rule}: more than one overlap fixture`]
    }
  })
  Array.concat(
    missing,
    samples
    ->Array.filter(fixture => !(rules->Array.includes(fixture.rule)))
    ->Array.map(fixture => `${fixture.rule}: fixture has no rule in Format.overlapping`),
  )
}

let diagnostics = (text, ~rule) => {
  try {
    switch JSON.parseOrThrow(text) {
    | Object(fields) =>
      switch (fields->Dict.get("diagnostics"), fields->Dict.get("number_of_files")) {
      | (Some(Array(found)), Some(Number(1.0))) =>
        let matches = found->Array.every(diagnostic =>
          switch diagnostic {
          | Object(fields) =>
            switch fields->Dict.get("code") {
            | Some(String(code)) => code->String.endsWith(`(${rule})`)
            | _ => false
            }
          | _ => false
          }
        )
        matches ? Ok(found->Array.length) : Error("unexpected diagnostic")
      | _ => Error("expected diagnostics for exactly one file")
      }
    | _ => Error("expected a linter report")
    }
  } catch {
  | _ => Error("invalid linter JSON")
  }
}

let output = answer => answer.Node.stdout->Nullable.getOr("")
let status = answer => answer.Node.status->Nullable.toOption

type spawnOptions = {
  cwd: string,
  encoding: string,
  input?: string,
  timeout: int,
  env: Dict.t<string>,
}
@module("node:child_process")
external spawn: (string, array<string>, spawnOptions) => Node.spawned = "spawnSync"

// Both tools are found by name, as mise's [env] path gives them to the fmt and lint tasks.
let environment = root => {
  let env = Node.envCopy(Node.env)
  let path = Node.env->Dict.get("PATH")->Option.getOr("")
  env->Dict.set("PATH", Node.join([root, "node_modules", ".bin"]) ++ ":" ++ path)
  env
}

let tools = (~root, ~scratch): tools => {
  let config = Node.join([root, ".oxlintrc.json"])
  let formatConfig = Node.join([root, ".oxfmtrc.json"])
  let file = Node.join([scratch, "example.ts"])
  let env = environment(root)
  {
    format: source => {
      let answer = spawn(
        "oxfmt",
        ["--config", formatConfig, "--stdin-filepath", file],
        {cwd: scratch, encoding: "utf8", input: source, timeout: 10000, env},
      )
      status(answer) == Some(0) ? Ok(output(answer)) : Error("oxfmt did not exit successfully")
    },
    lint: (rule, source) => {
      Node.writeFileSync(file, source)
      let answer = spawn(
        "oxlint",
        [
          "--config",
          config,
          "--disable-nested-config",
          "--no-ignore",
          "-A",
          "all",
          "-D",
          rule,
          "--format",
          "json",
          file,
        ],
        {cwd: scratch, encoding: "utf8", timeout: 10000, env},
      )
      switch status(answer) {
      | Some(0) | Some(1) =>
        switch diagnostics(output(answer), ~rule) {
        | Ok(count) if status(answer) != Some(count > 0 ? 1 : 0) =>
          Error("linter status disagrees with diagnostics")
        | result => result
        }
      | _ => Error("oxlint did not exit with a lint status")
      }
    },
  }
}

let main = (~root) => {
  let scratch = Node.mkdtempSync(Node.join([Node.tmpdir(), "overlap-"]))
  try {
    let found = held(tools(~root, ~scratch))
    Node.rmSync(scratch, {recursive: true, force: true})
    found
  } catch {
  | error =>
    Node.rmSync(scratch, {recursive: true, force: true})
    throw(error)
  }
}
