/**
 * Names a background job started and gone silent, so the agent looks at it,
 * long-command-background.
 */
type job = {id: string, description: string, output: string, targets: array<string>}
type stale = {job: job, silent: int, marker: float}
type call = {description: string, command: string, cwd: string}

/**
 * What the transcript has said so far, kept in the ledger so each call reads only what was
 * appended.
 */
type state = {
  v: int,
  mutable offset: float,
  calls: Dict.t<call>,
  mutable stopCalls: array<string>,
  mutable jobs: array<job>,
  mutable ended: array<string>,
  mutable stops: array<string>,
  posts: Dict.t<float>,
  mutable last: array<string>,
}

@get external mtimeMs: Node.stats => float = "mtimeMs"
@get external size: Node.stats => float = "size"
@val external now: unit => float = "Date.now"
external toState: JSON.t => state = "%identity"

type bytes
@module("node:fs") external openSync: (string, @as("r") _) => int = "openSync"
@module("node:fs") external closeSync: int => unit = "closeSync"
@module("node:fs") external readSync: (int, bytes, int, int, float) => int = "readSync"
@val @scope("Buffer") external alloc: int => bytes = "alloc"
@val @scope("Buffer") external concat: array<bytes> => bytes = "concat"
@send external lastIndexOf: (bytes, int) => int = "lastIndexOf"
@send external subarray: (bytes, int, int) => bytes = "subarray"
@send external decode: (bytes, @as("utf8") _, int, int) => string = "toString"
@get external byteLength: bytes => int = "length"

/** A description holding this word marks a job silent by design, which is never named. */
let quiet = Delegation.quietMark
let version = 1
/** How much of the end of a transcript the first call reads, and the chunk each read takes. */
let firstReadBytes =
  64. *. 1048576.
let chunkBytes = 1048576
/**
 * A job is said at most this often by a post-tool call, and never past `giveUpSeconds` of silence.
 */
let repeatSeconds = 300
let giveUpSeconds = 3600
let endedKept = 2000

let startedAs = /Command running in background with ID: ([A-Za-z0-9_-]+)\. Output is being written to: (.+?)\. You will/
let stoppedAs = /Successfully stopped task: ([A-Za-z0-9_-]+)/
let taskIdAs = /<task-id>([^<]+)<\/task-id>/
let redirectAs = /^(?:\d*|&)>>?(.*)$/
let heredocAs = /<<-?\s*(['"]?)([A-Za-z_][A-Za-z0-9_]*)\1/

let capture = (found: option<RegExp.Result.t>, at) =>
  found->Option.flatMap(result => result->Array.get(at))->Option.flatMap(text => text)

/**
 * Streams the complete lines of `path` from `from` to `until` to `onLine`, and returns the offset
 * after them.
 */
let eachLine = (path, ~from, ~until, ~dropFirst, onLine) => {
  let fd = openSync(path)
  try {
    let chunk = alloc(chunkBytes)
    let carry = ref(alloc(0))
    let position = ref(from)
    let consumed = ref(from)
    let skipping = ref(dropFirst)
    let reading = ref(true)
    while reading.contents && position.contents < until {
      let want = Math.min(chunkBytes->Int.toFloat, until -. position.contents)->Float.toInt
      let got = readSync(fd, chunk, 0, want, position.contents)
      if got <= 0 {
        reading := false
      } else {
        position := position.contents +. got->Int.toFloat
        let data = concat([carry.contents, subarray(chunk, 0, got)])
        let cut = data->lastIndexOf(10)
        if cut >= 0 {
          decode(data, 0, cut)
          ->String.split("\n")
          ->Array.forEach(line =>
            if skipping.contents {
              skipping := false
            } else {
              onLine(line)
            }
          )
          consumed := consumed.contents +. (cut + 1)->Int.toFloat
          carry := concat([subarray(data, cut + 1, data->byteLength)])
        } else {
          carry := concat([data])
        }
      }
    }
    closeSync(fd)
    consumed.contents
  } catch {
  | error =>
    closeSync(fd)
    throw(error)
  }
}

/** The command without the body of each here-document, which is text and not run. */
let withoutHeredocs = command => {
  let kept = []
  let ending = ref(None)
  command
  ->String.split("\n")
  ->Array.forEach(line =>
    switch ending.contents {
    | Some(delimiter) => line->String.trim == delimiter ? ending := None : ()
    | None =>
      kept->Array.push(line)
      ending := heredocAs->RegExp.exec(line)->capture(2)
    }
  )
  kept->Array.join("\n")
}

/** The files a background command redirects to, which grow while it lives. */
let targetsOf = (command, ~cwd) => {
  let words = Jj_command.words(withoutHeredocs(command))->Option.getOr([])
  let found = []
  words->Array.forEachWithIndex((word, at) =>
    switch redirectAs->RegExp.exec(word)->capture(1) {
    | None => ()
    | Some(rest) =>
      let target = rest == "" ? words[at + 1]->Option.getOr("") : rest
      if (
        target == "" ||
        target->String.startsWith("&") ||
        target->String.startsWith("/dev/") ||
        target->String.includes("$") ||
        target->String.includes("`")
      ) {
        ()
      } else if target->String.startsWith("/") {
        found->Array.push(target)
      } else if target->String.startsWith("~/") {
        found->Array.push(
          Node.join([Node.env->Dict.get("HOME")->Option.getOr(""), target->String.slice(~start=2)]),
        )
      } else if cwd != "" {
        found->Array.push(Node.join([cwd, target]))
      }
    }
  )
  found
}

let fresh = (): state => {
  v: version,
  offset: -1.,
  calls: Dict.make(),
  stopCalls: [],
  jobs: [],
  ended: [],
  stops: [],
  posts: Dict.make(),
  last: [],
}

let finish = (state: state, id) => {
  state.jobs = state.jobs->Array.filter(job => job.id != id)
  state.ended->Array.push(id)
  if state.ended->Array.length > endedKept {
    state.ended = state.ended->Array.slice(~start=endedKept / 2)
  }
}

/** The text of a tool result or message content, in whichever shape it was written. */
let textsOf = (content: option<JSON.t>) =>
  switch content {
  | Some(JSON.String(text)) => [text]
  | Some(JSON.Array(parts)) =>
    parts->Array.filterMap(part =>
      switch part {
      | JSON.Object(fields) => fields->Payload.text("text")
      | _ => None
      }
    )
  | _ => []
  }

let interesting = line =>
  [
    "run_in_background",
    "Output is being written to",
    "TaskStop",
    "task-notification",
    "Successfully stopped",
  ]->Array.some(word => line->String.includes(word))

/** Task ids a harness notice names, a notice being a message that begins with the tag. */
let noticed = (fields: Payload.t) => {
  let texts = []
  switch (fields->Payload.text("type"), fields->Payload.text("operation")) {
  | (Some("queue-operation"), Some("enqueue")) =>
    fields->Payload.text("content")->Option.forEach(text => texts->Array.push(text))
  | _ => ()
  }
  fields
  ->Payload.object("attachment")
  ->Option.flatMap(attachment => attachment->Payload.text("prompt"))
  ->Option.forEach(text => texts->Array.push(text))
  if fields->Payload.text("type") == Some("user") {
    fields
    ->Payload.object("message")
    ->Option.forEach(message => {
      let content = message->Dict.get("content")
      switch content {
      | Some(JSON.String(text)) => texts->Array.push(text)
      | Some(JSON.Array(parts)) =>
        parts->Array.forEach(part =>
          switch part {
          | JSON.Object(item) if item->Payload.text("type") == Some("text") =>
            item->Payload.text("text")->Option.forEach(text => texts->Array.push(text))
          | _ => ()
          }
        )
      | _ => ()
      }
    })
  }
  texts
  ->Array.filter(text => text->String.trim->String.startsWith("<task-notification>"))
  ->Array.filterMap(text => taskIdAs->RegExp.exec(text)->capture(1))
}

/**
 * Takes one transcript line into the state, from the exact structured place each fact is written.
 */
let feed = (state: state, line, ~session) =>
  if interesting(line) {
    switch Payload.parse(line) {
    | None => ()
    | Some(fields) =>
      let foreign = switch (session, fields->Payload.text("sessionId")) {
      | (Some(mine), Some(theirs)) => mine != theirs
      | _ => false
      }
      if !foreign {
        noticed(fields)->Array.forEach(id => state->finish(id))
        let kind = fields->Payload.text("type")
        let items = switch fields
        ->Payload.object("message")
        ->Option.flatMap(m => m->Dict.get("content")) {
        | Some(JSON.Array(parts)) if kind == Some("user") || kind == Some("assistant") => parts
        | _ => []
        }
        items->Array.forEach(item =>
          switch item {
          | JSON.Object(part) =>
            switch (part->Payload.text("type"), part->Payload.text("id")) {
            | (Some("tool_use"), Some(id)) =>
              switch (part->Payload.text("name"), part->Payload.object("input")) {
              | (Some("Bash"), Some(input)) if input->Payload.flag("run_in_background") =>
                state.calls->Dict.set(
                  id,
                  {
                    description: input->Payload.text("description")->Option.getOr(""),
                    command: input->Payload.text("command")->Option.getOr(""),
                    cwd: fields->Payload.text("cwd")->Option.getOr(""),
                  },
                )
              | (Some("TaskStop"), _) => state.stopCalls->Array.push(id)
              | _ => ()
              }
            | _ =>
              switch (part->Payload.text("type"), part->Payload.text("tool_use_id")) {
              | (Some("tool_result"), Some(id)) =>
                let text = textsOf(part->Dict.get("content"))->Array.join("\n")
                switch state.calls->Dict.get(id) {
                | Some(call) =>
                  state.calls->Dict.delete(id)
                  let found = startedAs->RegExp.exec(text)
                  switch (found->capture(1), found->capture(2)) {
                  | (Some(job), Some(output)) if !(state.ended->Array.includes(job)) =>
                    state.jobs->Array.push({
                      id: job,
                      output,
                      description: call.description,
                      targets: targetsOf(call.command, ~cwd=call.cwd),
                    })
                  | _ => ()
                  }
                | None => ()
                }
                if state.stopCalls->Array.includes(id) {
                  state.stopCalls = state.stopCalls->Array.filter(call => call != id)
                  stoppedAs
                  ->RegExp.exec(text)
                  ->capture(1)
                  ->Option.forEach(job => state->finish(job))
                }
              | _ => ()
              }
            }
          | _ => ()
          }
        )
      }
    }
  }

/** The ledger of one session, and of one subagent within it. */
let ledger = (payload: Payload.t) =>
  Node.join([
    Node.tmpdir(),
    `stale-jobs-${payload->Payload.text("session_id")->Option.getOr("unknown")}${payload
      ->Payload.text("agent_id")
      ->Option.filter(id => id != "")
      ->Option.mapOr("", id => "-" ++ id)}.json`,
  ])

let load = path =>
  try {
    switch JSON.parseOrThrow(Node.readFileSync(path)) {
    | JSON.Object(fields) as json
      if fields->Dict.get("v") == Some(JSON.Number(version->Int.toFloat)) =>
      toState(json)
    | _ => fresh()
    }
  } catch {
  | _ => fresh()
  }

let save = (path, state) =>
  try Node.writeFileSync(path, JSON.stringifyAny(state)->Option.getOr("")) catch {
  | _ => ()
  }

/** The transcript to read, the parent's for a session and its own file for a subagent, or none. */
let transcriptOf = (payload: Payload.t) =>
  switch payload->Payload.text("transcript_path") {
  | Some(path) if path != "" =>
    switch payload->Payload.text("agent_id") {
    | Some(agent) if agent != "" =>
      let own = Node.join([
        path->String.replaceRegExp(/\.jsonl$/, ""),
        "subagents",
        `agent-${agent}.jsonl`,
      ])
      own->Node.existsSync ? Some(own) : None
    | _ => Some(path)
    }
  | _ => None
  }

/** The state brought up to the end of the transcript, reading only what was appended. */
let observe = (payload: Payload.t): result<option<state>, string> =>
  switch transcriptOf(payload) {
  | None => Ok(None)
  | Some(path) =>
    try {
      switch Node.statMaybe(path, {throwIfNoEntry: false})->Nullable.toOption {
      | None => Error(`it could not read the transcript ${path}`)
      | Some(stats) =>
        let length = stats->size
        let place = ledger(payload)
        let loaded = load(place)
        let state = loaded.offset > length ? fresh() : loaded
        let first = state.offset < 0.
        let from = first ? Math.max(0., length -. firstReadBytes) : state.offset
        let session = payload->Payload.text("session_id")
        state.offset = eachLine(path, ~from, ~until=length, ~dropFirst=first && from > 0., line =>
          state->feed(line, ~session)
        )
        save(place, state)
        Ok(Some(state))
      }
    } catch {
    | _ => Error(`it could not read the transcript ${path}`)
    }
  }

/**
 * The jobs silent for `stallSeconds` or more, by the latest time `mtime` gives their output or
 * redirects.
 */
let stale = (jobs: array<job>, ~at, ~mtime): array<stale> =>
  jobs->Array.filterMap(job =>
    if job.description->String.toLowerCase->String.includes(quiet) {
      None
    } else {
      let times = Array.concat([job.output], job.targets)->Array.filterMap(mtime)
      times
      ->Array.reduce(None, (best, time) =>
        switch best {
        | Some(held) if held >= time => best
        | _ => Some(time)
        }
      )
      ->Option.flatMap(marker => {
        let silent = Float.toInt((at -. marker) /. 1000.)
        silent >= Delegation.stallSeconds ? Some({job, silent, marker}) : None
      })
    }
  )

let modified = path =>
  Node.statMaybe(path, {throwIfNoEntry: false})->Nullable.toOption->Option.map(mtimeMs)

let describe = (found: stale) =>
  `Background job ${found.job.id} (${found.job.description}) has been silent for ${Int.toString(
      found.silent,
    )} seconds. Look at it now: read ${found.job.output}, or run \`mise run watch ${found.job.output}\` under Monitor. A job that is hung never sends its completion notice.`

let finalNote = (found: stale) =>
  `${describe(found)} It has been silent over an hour, so this is the last time it is said.`

/** Every silent job of the session, or none where the transcript cannot be read. */
let find = (payload: Payload.t, ~at=now(), ~mtime=modified): result<array<stale>, string> =>
  try {
    switch observe(payload) {
    | Ok(Some(state)) => Ok(state.jobs->stale(~at, ~mtime))
    | Ok(None) => Ok([])
    | Error(why) => Error(why)
    }
  } catch {
  | _ => Ok([])
  }

/**
 * The post-tool observation, each silent job at most every five minutes, and a last word at an
 * hour.
 */
let context = (payload: Payload.t, ~at=now(), ~mtime=modified): option<string> =>
  try {
    switch observe(payload) {
    | Ok(Some(state)) =>
      let lines =
        state.jobs
        ->stale(~at, ~mtime)
        ->Array.filterMap(found => {
          let id = found.job.id
          if found.silent >= giveUpSeconds {
            if state.last->Array.includes(id) {
              None
            } else {
              state.last->Array.push(id)
              Some(finalNote(found))
            }
          } else {
            switch state.posts->Dict.get(id) {
            | Some(before) if at -. before < repeatSeconds->Int.toFloat *. 1000. => None
            | _ =>
              state.posts->Dict.set(id, at)
              Some(describe(found))
            }
          }
        })
      if lines == [] {
        None
      } else {
        save(ledger(payload), state)
        Some(lines->Array.join("\n"))
      }
    | _ => None
    }
  } catch {
  | _ => None
  }

let mark = (found: stale) => `${found.job.id} ${Float.toString(found.marker)}`

/** The hold a stop makes, once for each job and silence, and a note where the transcript failed. */
let response = (payload: Payload.t, ~at=now(), ~mtime=modified): option<JSON.t> =>
  if payload->Payload.flag("stop_hook_active") {
    None
  } else {
    let object = fields => Some(JSON.Object(Dict.fromArray(fields)))
    try {
      switch observe(payload) {
      | Error(why) =>
        object([
          (
            "systemMessage",
            JSON.String(`Stale background jobs were not checked: ${why}. The stop went through.`),
          ),
        ])
      | Ok(None) => None
      | Ok(Some(state)) =>
        switch state.jobs
        ->stale(~at, ~mtime)
        ->Array.filter(found => !(state.stops->Array.includes(mark(found)))) {
        | [] => None
        | news =>
          state.stops = state.stops->Array.concat(news->Array.map(mark))
          save(ledger(payload), state)
          object([
            ("decision", JSON.String("block")),
            ("reason", JSON.String(news->Array.map(describe)->Array.join("\n"))),
          ])
        }
      }
    } catch {
    | _ => None
    }
  }
