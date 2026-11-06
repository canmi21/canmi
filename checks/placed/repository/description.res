/** A repository's forge description against model/rules/readme.res, one short sentence, which a
 private repository may go without. */
let fewest = 4
let most = 8

type described = {repo: string, description: option<string>, isPrivate: bool}

let sentenceBreak = /[.!?]\s+\S/

/** What a description breaks, or none where it is one sentence of four to eight words. */
let problem = (text: string) => {
  let text = text->String.trim
  let words = text->String.split(" ")->Array.filter(word => word != "")->Array.length
  if text == "" {
    Some("has no description")
  } else if !(text->String.endsWith(".")) {
    Some(`"${text}" does not end in a full stop`)
  } else if sentenceBreak->RegExp.test(text) {
    Some(`"${text}" is more than one sentence`)
  } else if words < fewest || words > most {
    Some(
      `"${text}" has ${Int.toString(words)} words, not ${Int.toString(fewest)} to ${Int.toString(
          most,
        )}`,
    )
  } else {
    None
  }
}

/** Each description that breaks the rule, named by its repository; a private one may have none. */
let problems = (described: array<described>) =>
  described->Array.filterMap(({repo, description, isPrivate}) => {
    let text = description->Option.getOr("")
    if isPrivate && text->String.trim == "" {
      None
    } else {
      problem(text)->Option.map(says => `${repo}: description ${says}`)
    }
  })

@scope("JSON") @val
external parse: string => {"description": Nullable.t<string>, "visibility": string} = "parse"

/** The description the forge holds for `user/repo` and whether it is private, or an error. */
let read = (~user, ~repo): result<(option<string>, bool), string> => {
  let ran = Node.spawnSync(
    "gh",
    ["repo", "view", `${user}/${repo}`, "--json", "description,visibility"],
    {encoding: "utf8", maxBuffer: 268435456},
  )
  if ran.status == Nullable.make(0) {
    try {
      let answer = parse(ran.stdout->Nullable.getOr(""))
      Ok((answer["description"]->Nullable.toOption, answer["visibility"] == "PRIVATE"))
    } catch {
    | _ => Error("an answer it cannot read")
    }
  } else {
    Error(ran.stderr->Nullable.getOr("")->String.trim->String.split("\n")->Array.getUnsafe(0))
  }
}

/** Every unpaused repository's description read from the forge, cloned or not. */
let main = (): array<string> => {
  Registry.registry()
  ->Array.filter(((path, _)) => Waiting.pauser(~repo=path)->Option.isNone)
  ->Array.flatMap(((path, (user, repo))) =>
    switch read(~user, ~repo) {
    | Ok((description, isPrivate)) => problems([{repo: path, description, isPrivate}])
    | Error(why) => [`${path}: description could not be read from the forge, ${why}`]
    }
  )
}
