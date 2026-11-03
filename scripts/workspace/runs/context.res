/**
 * A session's context size and compactions, read from its Claude transcript, one JSON object a
 * line. The format is internal, so what cannot be read is `Unreadable`, never zero.
 */
type outcome = Read({tokens: int, compactions: int}) | Unreadable(string)

type buffer
@module("node:fs") external openSync: (string, @as("r") _) => int = "openSync"
@module("node:fs") external readSync: (int, buffer, int, int, float) => int = "readSync"
@module("node:fs") external closeSync: int => unit = "closeSync"
@scope("Buffer") @val external allocate: int => buffer = "alloc"
@send external textOf: (buffer, string, int, int) => string = "toString"
@get external size: Node.stats => float = "size"

/** How much of the file's end is read for the last message, widened when it holds none. */
let tailBytes = [1048576, 8388608, 67108864]
let chunkBytes = 8388608
let marker = "compact_boundary"

/** The number in a usage object, or why it is not there. */
let tokensIn = (usage: Payload.t, key) =>
  switch usage->Dict.get(key) {
  | Some(JSON.Number(value)) if value >= 0. => Ok(value->Float.toInt)
  | _ => Error(`usage has no ${key}`)
  }

/** The context size one assistant line states, None where the line is no assistant message. */
let sizeOfLine = (line: string): option<result<int, string>> =>
  switch Payload.parse(line) {
  | Some(fields)
    if fields->Payload.text("type") == Some("assistant") &&
      !(fields->Payload.flag("isSidechain")) =>
    fields
    ->Payload.object("message")
    ->Option.flatMap(message => message->Payload.object("usage"))
    ->Option.map(usage =>
      ["input_tokens", "cache_read_input_tokens", "cache_creation_input_tokens", "output_tokens"]
      ->Array.map(tokensIn(usage, _))
      ->Array.reduce(Ok(0), (total, one) =>
        switch (total, one) {
        | (Ok(sum), Ok(value)) => Ok(sum + value)
        | (Error(why), _) | (_, Error(why)) => Error(why)
        }
      )
    )
    // A message the client made itself states no usage at all.
    ->Option.flatMap(size =>
      switch size {
      | Ok(0) => None
      | _ => Some(size)
      }
    )
  | _ => None
  }

/** The size the last assistant line of `text` states, a cut first line passed over. */
let lastSize = (text: string, ~whole) => {
  let lines = text->String.split("\n")
  let usable = whole ? lines : lines->Array.slice(~start=1)
  usable->Array.reduceRight(None, (found, line) =>
    switch found {
    | Some(_) => found
    | None => line->String.includes("\"usage\"") ? sizeOfLine(line) : None
    }
  )
}

/** Whether one line is a compaction boundary, as an entry and never as a message quoting one. */
let isBoundary = (line: string) =>
  line->String.includes(marker) &&
    switch Payload.parse(line) {
    | Some(fields) =>
      fields->Payload.text("type") == Some("system") &&
        fields->Payload.text("subtype") == Some(marker)
    | None => false
    }

/** The context size from the end of the file alone, the read widened while it finds none. */
let sizeOf = (path): result<int, string> =>
  switch Node.stat(path) {
  | None => Error("no transcript at the path")
  | Some(stats) =>
    let total = stats->size
    let descriptor = openSync(path)
    let found = ref(None)
    let covered = ref(total <= 0.)
    try {
      tailBytes->Array.forEach(want => {
        if found.contents == None && !covered.contents {
          let length = Math.min(want->Int.toFloat, total)->Float.toInt
          covered := length->Int.toFloat >= total
          let place = allocate(length)
          let got = readSync(descriptor, place, 0, length, total -. length->Int.toFloat)
          found := lastSize(place->textOf("latin1", 0, got), ~whole=covered.contents)
        }
      })
    } catch {
    | _ => found := Some(Error("the end of the transcript could not be read"))
    }
    closeSync(descriptor)
    found.contents->Option.getOr(Error("no assistant message with usage in the file"))
  }

/** When one line shows the session itself at work, a queued notice written for it never does. */
let turnOfLine = (line: string) =>
  line->String.includes("\"timestamp\"")
    ? Payload.parse(line)->Option.flatMap(fields =>
        ["assistant", "api-request"]->Array.includes(Ledger.textOf(fields, "type"))
          ? fields
            ->Payload.text("timestamp")
            ->Option.map(text => Date.fromString(text)->Date.getTime)
            ->Option.filter(Float.isFinite)
          : None
      )
    : None

/** The session's last turn from its transcript's end, the read widened while it finds none. */
let lastTurn = (path): option<float> =>
  switch Node.stat(path) {
  | None => None
  | Some(stats) =>
    let total = stats->size
    let descriptor = openSync(path)
    let found = ref(None)
    let covered = ref(total <= 0.)
    try {
      tailBytes->Array.forEach(want => {
        if found.contents == None && !covered.contents {
          let length = Math.min(want->Int.toFloat, total)->Float.toInt
          covered := length->Int.toFloat >= total
          let place = allocate(length)
          let got = readSync(descriptor, place, 0, length, total -. length->Int.toFloat)
          let lines = place->textOf("latin1", 0, got)->String.split("\n")
          found :=
            (covered.contents ? lines : lines->Array.slice(~start=1))->Array.reduceRight(None, (
              last,
              line,
            ) => last != None ? last : turnOfLine(line))
        }
      })
    } catch {
    | _ => ()
    }
    closeSync(descriptor)
    found.contents
  }

/** Every compaction boundary in the file, read in chunks so no whole transcript is held. */
let countIn = (path): result<int, string> =>
  switch Node.stat(path) {
  | None => Error("no transcript at the path")
  | Some(_) =>
    let descriptor = openSync(path)
    let place = allocate(chunkBytes)
    let count = ref(0)
    let carry = ref("")
    let outcome = try {
      let position = ref(0.)
      let reading = ref(true)
      while reading.contents {
        let got = readSync(descriptor, place, 0, chunkBytes, position.contents)
        position := position.contents +. got->Int.toFloat
        let lines = (carry.contents ++ place->textOf("latin1", 0, got))->String.split("\n")
        carry := lines->Array.pop->Option.getOr("")
        lines->Array.forEach(line => count := count.contents + (isBoundary(line) ? 1 : 0))
        reading := got > 0
      }
      count := count.contents + (isBoundary(carry.contents) ? 1 : 0)
      Ok(count.contents)
    } catch {
    | _ => Error("the transcript could not be read through")
    }
    closeSync(descriptor)
    outcome
  }

/** A cached count is `{"at":ms,"count":n}` in a file named for the transcript. */
let cachedCount = (file, ~now) =>
  Node.existsSync(file)
    ? try {
        Payload.parse(Node.readFileSync(file))->Option.flatMap(fields => {
          let at = Ledger.numberOf(fields, "at")
          let count = Ledger.numberOf(fields, "count")
          switch (at, count) {
          | (Some(at), Some(count))
            if now -. at < Delegation.figuresSeconds->Int.toFloat *. 1000. =>
            Some(count->Float.toInt)
          | _ => None
          }
        })
      } catch {
      | _ => None
      }
    : None

/** The compactions, counted again no oftener than `Delegation.figuresSeconds`. */
let compactionsOf = (path, ~cache, ~now): result<int, string> => {
  let file = Node.join([cache, `${Node.basename(path)}.json`])
  switch cachedCount(file, ~now) {
  | Some(count) => Ok(count)
  | None =>
    countIn(path)->Result.map(count => {
      try {
        Node.mkdirAll(cache)
        Node.writeFileSync(file, `{"at":${Float.toString(now)},"count":${Int.toString(count)}}`)
      } catch {
      | _ => ()
      }
      count
    })
  }
}

/** A session's context size and compactions, or why they could not be read. */
let read = (path, ~cache, ~now) =>
  switch (sizeOf(path), compactionsOf(path, ~cache, ~now)) {
  | (Ok(tokens), Ok(compactions)) => Read({tokens, compactions})
  | (Error(why), _) | (_, Error(why)) => Unreadable(why)
  }

/** The share of the window a size fills. */
let share = tokens => tokens->Int.toFloat /. Delegation.contextWindowTokens->Int.toFloat

/** Whether an advisor holding this much is past the share at which it is replaced. */
let due = tokens => share(tokens) >= Delegation.advisorReplacedFrom
