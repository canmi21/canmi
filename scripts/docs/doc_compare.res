/**
 * A doc against its original on headings, bold leads and code spans, the last step of a scribe,
 * docs/agents/seats/scribe.md. Run as `mise run compare <original> <edited>`.
 */
type parts = {headings: array<string>, leads: array<string>, spans: array<string>}

let fence = /^\s*(```|~~~)/
let heading = /^#{1,6}\s+\S/
let inline = /(`+)[^`]+?\1/g
let marker = /^(\s*>\s*)*\s*(?:(?:[-*+]|\d+[.)])\s+)?/

/** The bold lead a paragraph opens with, past a list marker or a quote, if it has one. */
let lead = (block: array<string>) => {
  let text = block->Array.join(" ")->String.replaceRegExp(marker, "")
  if text->String.startsWith("**") {
    let close = text->String.indexOfFrom("**", 2)
    close > 2 ? Some(text->String.slice(~start=0, ~end=close + 2)) : None
  } else {
    None
  }
}

let read = (text): parts => {
  let headings = []
  let leads = []
  let spans = []
  let block = ref([])
  let code = ref(None)
  let flush = () => {
    lead(block.contents)->Option.forEach(found => leads->Array.push(found))
    block := []
  }
  text
  ->String.split("\n")
  ->Array.forEach(line =>
    switch code.contents {
    | Some(held) =>
      if fence->RegExp.test(line) {
        spans->Array.push(held->Array.join("\n"))
        code := None
      } else {
        held->Array.push(line)
      }
    | None if fence->RegExp.test(line) =>
      flush()
      code := Some([])
    | None =>
      if line->String.trim == "" {
        flush()
      } else {
        if heading->RegExp.test(line) {
          flush()
          headings->Array.push(line->String.trim)
        } else {
          block.contents->Array.push(line->String.trim)
        }
        line
        ->String.match(inline)
        ->Option.forEach(found =>
          found->Array.forEach(span => span->Option.forEach(span => spans->Array.push(span)))
        )
      }
    }
  )
  flush()
  {headings, leads, spans}
}

/** What `before` holds that `after` does not, each item matched once. */
let lost = (before: array<string>, after: array<string>) => {
  let left = after->Array.copy
  before->Array.filter(item =>
    switch left->Array.indexOf(item) {
    | -1 => true
    | at =>
      left->Array.splice(~start=at, ~remove=1, ~insert=[])
      false
    }
  )
}

/** Each difference as a line, the kind first, what the edit lost or added after it. */
let compare = (original: string, edited: string): array<string> => {
  let (a, b) = (read(original), read(edited))
  [
    ("heading", a.headings, b.headings),
    ("bold lead", a.leads, b.leads),
    ("code span", a.spans, b.spans),
  ]->Array.flatMap(((kind, before, after)) =>
    Array.concat(
      lost(before, after)->Array.map(item => `lost ${kind}: ${item}`),
      lost(after, before)->Array.map(item => `added ${kind}: ${item}`),
    )
  )
}

if Node.isMain {
  switch Node.args() {
  | [original, edited] =>
    let found = compare(Node.readFileSync(original), Node.readFileSync(edited))
    found->Array.forEach(line => Console.log(`  x ${line}`))
    if found == [] {
      Console.log("  headings, bold leads and code spans are as the original has them")
    }
    Node.exit(found == [] ? 0 : 1)
  | _ =>
    Console.error("compare <original> <edited>: the two files to compare")
    Node.exit(2)
  }
}
