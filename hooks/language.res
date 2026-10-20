/**
 * At the end of a turn: hold it while the reply it ends with speaks English to a user who wrote
 * Chinese -- docs/voice.md. The reply is the prose after the last tool call; a short block, a path
 * or a command is not prose, and a user who wrote English is answered in English. Both harnesses'
 * transcripts are read, and the payload's last message where there is none.
 */
let chinese = RegExp.fromString("[\\u3400-\\u4dbf\\u4e00-\\u9fff\\uf900-\\ufaff]")
let fenced = /```[\s\S]*?```/g
let inline = /`[^`\n]*`/g
let latin = /[A-Za-z]/g
/** Fewer letters than this is a word, a path or a command, not a reply written in a language. */
let proseLetters = 60
/** What the harness writes in the user's place: injected context, and another session's message. */
let harness = ["<", "Another Claude session sent a message"]

let english = text => {
  let prose = text->String.replaceRegExp(fenced, "")->String.replaceRegExp(inline, "")
  let letters = prose->String.match(latin)->Option.mapOr(0, Array.length)
  letters >= proseLetters && !(chinese->RegExp.test(prose))
}

/** The text parts of a message's content, whichever shape the harness wrote it in. */
let texts = (content: option<JSON.t>, kinds) =>
  switch content {
  | Some(JSON.String(text)) => [text]
  | Some(JSON.Array(parts)) =>
    parts->Array.filterMap(part =>
      switch part {
      | JSON.Object(fields) =>
        switch (fields->Payload.text("type"), fields->Payload.text("text")) {
        | (Some(kind), Some(text)) if kinds->Array.includes(kind) => Some(text)
        | _ => None
        }
      | _ => None
      }
    )
  | _ => []
  }

type role = Assistant | Tool | User

let opensWith = (parts, prefixes) =>
  parts[0]->Option.mapOr(false, first =>
    prefixes->Array.some(prefix => first->String.trimStart->String.startsWith(prefix))
  )

/** One transcript line as its role, its texts and whether the user spoke it, or none. */
let entry = (line): option<(role, array<string>, bool)> =>
  switch Payload.parse(line) {
  | None => None
  | Some(record) =>
    switch record->Payload.text("type") {
    | Some(("user" | "assistant") as kind) =>
      record
      ->Payload.object("message")
      ->Option.map(message => {
        let parts = texts(message->Dict.get("content"), ["text"])
        if kind == "assistant" {
          (Assistant, parts, false)
        } else if parts == [] {
          // A tool's result: neither side speaking, and the end of whatever was written before it.
          (Tool, [], false)
        } else {
          // Claude Code marks a person's message `origin: {"kind": "human"}`; another session's
          // arrives in the user's place without it, in English.
          let spoken = switch record
          ->Payload.object("origin")
          ->Option.flatMap(origin => origin->Payload.text("kind")) {
          | Some(origin) => origin == "human"
          | None => !(record->Payload.flag("isMeta")) && !opensWith(parts, harness)
          }
          (User, parts, spoken)
        }
      })
    | Some("response_item") =>
      record
      ->Payload.object("payload")
      ->Option.flatMap(item =>
        switch (item->Payload.text("type"), item->Payload.text("role")) {
        | (Some("function_call_output" | "custom_tool_call_output"), _) => Some((Tool, [], false))
        | (Some("message"), Some("assistant")) =>
          Some((Assistant, texts(item->Dict.get("content"), ["output_text"]), false))
        | (Some("message"), Some(("user" | "developer") as role)) =>
          let parts = texts(item->Dict.get("content"), ["input_text"])
          Some((User, parts, role == "user" && parts != [] && !opensWith(parts, ["<", "#"])))
        | _ => None
        }
      )
    | _ => None
    }
  }

/** What the user last said, and the reply written after the last tool call. */
let turn = (transcript: string): (option<string>, array<string>) => {
  let asked = ref(None)
  let written = ref([])
  transcript
  ->String.split("\n")
  ->Array.forEach(line =>
    switch entry(line) {
    | Some((Assistant, parts, _)) => written := Array.concat(written.contents, parts)
    | Some((_, parts, spoken)) =>
      written := []
      if spoken {
        asked := Some(parts->Array.join("\n"))
      }
    | None => ()
    }
  )
  (asked.contents, written.contents)
}

let response = (payload: Payload.t): option<JSON.t> => {
  let (asked, written) = switch payload->Payload.text("transcript_path") {
  | Some(path) if path != "" =>
    try turn(Node.readFileSync(path)) catch {
    | _ => (None, [])
    }
  | _ => (None, [])
  }
  let written = switch (written, payload->Payload.text("last_assistant_message")) {
  | ([], Some(last)) => [last]
  | _ => written
  }
  let answeredInEnglish = asked->Option.mapOr(false, asked => !(chinese->RegExp.test(asked)))
  if answeredInEnglish || !(written->Array.some(english)) {
    None
  } else {
    let reason =
      "This turn spoke to the user in English. docs/voice.md: the chat is simplified Chinese, " ++
      "with English technical nouns kept as they are; only file content is English. Restate " ++
      "what you told the user in Chinese -- the result, what is pending, what to check -- and " ++ "then finish the turn."
    Some(
      JSON.Object(
        Dict.fromArray([("decision", JSON.String("block")), ("reason", JSON.String(reason))]),
      ),
    )
  }
}
