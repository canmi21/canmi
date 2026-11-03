type phases = {
  warmup: float,
  reads: int,
  editing: float,
  checks: float,
  whole: float,
}

type call = {id: string, name: string, command: string}
type line = {at: float, calls: array<call>, results: array<string>}

let items = (fields: Payload.t) =>
  switch fields
  ->Payload.object("message")
  ->Option.flatMap(message => message->Dict.get("content")) {
  | Some(JSON.Array(items)) =>
    items->Array.filterMap(item =>
      switch item {
      | JSON.Object(one) => Some(one)
      | _ => None
      }
    )
  | _ => []
  }

let lineOf = text =>
  text
  ->Payload.parse
  ->Option.flatMap(fields =>
    fields
    ->Payload.text("timestamp")
    ->Option.flatMap(Rounds.timeOf)
    ->Option.map(at => {
      let found = items(fields)
      {
        at,
        calls: found->Array.filterMap(
          one =>
            one->Payload.text("type") == Some("tool_use")
              ? Some({
                  id: one->Payload.text("id")->Option.getOr(""),
                  name: one->Payload.text("name")->Option.getOr(""),
                  command: one
                  ->Payload.object("input")
                  ->Option.flatMap(input => input->Payload.text("command"))
                  ->Option.getOr(""),
                })
              : None,
        ),
        results: found->Array.filterMap(
          one =>
            one->Payload.text("type") == Some("tool_result")
              ? one->Payload.text("tool_use_id")
              : None,
        ),
      }
    })
  )

let isEdit = call => call.name == "Edit" || call.name == "Write"

let isRead = call =>
  call.name == "Read" ||
  call.name == "Grep" ||
  call.name == "Glob" ||
  (call.name == "Bash" && /^\s*(cat|sed|grep|head|ls)(\s|$)/->RegExp.test(call.command))

let isCheck = call =>
  call.name == "Bash" &&
    (call.command->String.includes("built") ||
    call.command->String.includes("lane check") ||
    call.command->String.includes("handed"))

let of_ = text => {
  let lines =
    text
    ->String.split("\n")
    ->Array.filter(one => !(one->String.includes("\"queue-operation\"")))
    ->Array.filterMap(lineOf)
  switch (lines[0], lines[lines->Array.length - 1]) {
  | (Some(first), Some(last)) =>
    let edited = lines->Array.findIndex(one => one.calls->Array.some(isEdit))
    if edited < 0 {
      None
    } else {
      let editAt = lines[edited]->Option.mapOr(first.at, one => one.at)
      let reads = ref(0)
      lines
      ->Array.slice(~start=0, ~end=edited + 1)
      ->Array.forEach(one => {
        let before = one.calls->Array.findIndex(isEdit)
        let counted = before < 0 ? one.calls : one.calls->Array.slice(~start=0, ~end=before)
        reads := reads.contents + counted->Array.filter(isRead)->Array.length
      })
      let checks = ref(0.)
      lines->Array.forEach(one =>
        one.calls->Array.forEach(call =>
          if isCheck(call) && one.at >= editAt {
            let ended =
              lines
              ->Array.find(other => other.at >= one.at && other.results->Array.includes(call.id))
              ->Option.mapOr(last.at, other => other.at)
            checks := checks.contents +. (ended -. one.at)
          }
        )
      )
      Some({
        warmup: (editAt -. first.at) /. 1000.,
        reads: reads.contents,
        editing: (last.at -. editAt) /. 1000.,
        checks: Math.min(checks.contents, last.at -. editAt) /. 1000.,
        whole: (last.at -. first.at) /. 1000.,
      })
    }
  | _ => None
  }
}
