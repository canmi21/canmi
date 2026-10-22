/**
 * What an RFC's file holds, its frontmatter and the sections of its body, held to RFC 2ut6h. Every
 * check answers with all the problems it found.
 */
type reference = {url: string, took: string, via: option<string>}

type front = {
  name: string,
  title: string,
  status: string,
  supersedes: array<string>,
  blockedBy: array<string>,
  commits: array<string>,
  references: array<reference>,
}

let keys = ["name", "title", "status", "supersedes", "blocked-by", "commits", "references"]

/** `repo@hash`, the repository `workspace` or a path repos/registry.toml lists. */
let commit = /^([a-z0-9-]+(?:\/[a-z0-9-]+)*)@([0-9a-f]{7,40})$/
let https = /^https:\/\/\S+$/

/** A file split into its frontmatter's text and its body. */
let split = (text): option<(string, string)> =>
  switch /^---\n([\s\S]*?)\n---\n?([\s\S]*)$/->RegExp.exec(text) {
  | Some(result) =>
    switch result->RegExp.Result.matches {
    | [Some(yaml), Some(body)] => Some((yaml, body))
    | [Some(yaml), None] => Some((yaml, ""))
    | _ => None
    }
  | None => None
  }

let body = text => split(text)->Option.mapOr(text, ((_, body)) => body)

/** Each check of one value pushes what is wrong with it to `found`, under its key. */
let textOf = (value: option<JSON.t>, ~at, ~found) =>
  switch value {
  | None =>
    found->Array.push(`\`${at}\` is missing`)
    ""
  | Some(String(text)) if text->String.trim != "" => text->String.trim
  | Some(_) =>
    found->Array.push(`\`${at}\` is empty`)
    ""
  }

let listOf = (value: option<JSON.t>, ~at, ~found, ~item: (JSON.t, string) => option<'a>) =>
  switch value {
  | None => []
  | Some(Array(items)) =>
    items->Array.filterMapWithIndex((one, index) => item(one, `${at}[${Int.toString(index)}]`))
  | Some(_) =>
    found->Array.push(`\`${at}\` is not a list`)
    []
  }

let matching = (pattern, ~says, ~found) =>
  (one: JSON.t, at) =>
    switch one {
    | String(text) if pattern->RegExp.test(text) => Some(text)
    | _ =>
      found->Array.push(`\`${at}\` ${says}`)
      None
    }

let referenceOf = (~found) =>
  (one: JSON.t, at) =>
    switch one {
    | Object(fields) =>
      fields
      ->Dict.keysToArray
      ->Array.forEach(key =>
        if !(["url", "took", "via"]->Array.includes(key)) {
          found->Array.push(`\`${at}.${key}\` is not a key the format has`)
        }
      )
      let address = (key, value: option<JSON.t>) =>
        switch value {
        | Some(String(text)) if https->RegExp.test(text) => Some(text)
        | _ =>
          found->Array.push(`\`${at}.${key}\` is not an https URL`)
          None
        }
      let url = address("url", fields->Dict.get("url"))
      let took = textOf(fields->Dict.get("took"), ~at=`${at}.took`, ~found)
      let via = fields->Dict.get("via")->Option.flatMap(via => address("via", Some(via)))
      url->Option.map(url => {url, took, via})
    | _ =>
      found->Array.push(`\`${at}\` is not a table of url, took and via`)
      None
    }

/** A file's frontmatter read, and every way it falls short. */
let readFront = (text): (option<front>, array<string>) =>
  switch split(text) {
  | None => (None, ["no frontmatter between --- lines"])
  | Some((yaml, _)) =>
    switch Yaml.parse(yaml) {
    | exception JsExn(error) => (
        None,
        [`frontmatter is not YAML: ${error->JsExn.message->Option.getOr("")}`],
      )
    | Object(fields) =>
      let found = []
      fields
      ->Dict.keysToArray
      ->Array.forEach(key =>
        if !(keys->Array.includes(key)) {
          found->Array.push(`\`${key}\` is not a key the format has`)
        }
      )
      let name = textOf(fields->Dict.get("name"), ~at="name", ~found)
      if name->String.length > 32 {
        found->Array.push("`name` is longer than 32 characters")
      }
      let title = textOf(fields->Dict.get("title"), ~at="title", ~found)
      let status = switch fields->Dict.get("status") {
      | Some(String(status)) if Planning.statuses->Array.includes(status) => status
      | None =>
        found->Array.push("`status` is missing")
        ""
      | Some(_) =>
        found->Array.push(`\`status\` is not one of ${Planning.statuses->Array.join(", ")}`)
        ""
      }
      let ids = key =>
        listOf(
          fields->Dict.get(key),
          ~at=key,
          ~found,
          ~item=matching(Rfc_name.id, ~says="is not an id", ~found),
        )
      let supersedes = ids("supersedes")
      let blockedBy = ids("blocked-by")
      let commits = listOf(
        fields->Dict.get("commits"),
        ~at="commits",
        ~found,
        ~item=matching(commit, ~says="is not repo@hash", ~found),
      )
      let references = switch fields->Dict.get("references") {
      | None =>
        found->Array.push("`references` is missing; write [] for our own idea")
        []
      | value => listOf(value, ~at="references", ~found, ~item=referenceOf(~found))
      }
      found == []
        ? (Some({name, title, status, supersedes, blockedBy, commits, references}), [])
        : (None, found)
    | _ => (None, ["frontmatter is not a table of keys"])
    }
  }

/** The body's second-level headings, outside fenced code. */
let sections = body => {
  let fenced = ref(false)
  body
  ->String.split("\n")
  ->Array.filterMap(line =>
    if /^(```|~~~)/->RegExp.test(line) {
      fenced := !fenced.contents
      None
    } else if !fenced.contents && line->String.startsWith("## ") {
      Some(line->String.slice(~start=3)->String.trim)
    } else {
      None
    }
  )
}

/**
 * Every way a body's sections stray from the four, their order, or the ones its status asks, none
 * asked where the status could not be read.
 */
let checkSections = (body, ~status: option<string>) => {
  let order = Planning.sections
  let found = sections(body)
  let problems =
    found->Array.filterMap(name =>
      order->Array.includes(name) ? None : Some(`unknown section \`${name}\``)
    )
  let known = found->Array.filter(name => order->Array.includes(name))
  let places = known->Array.map(name => order->Array.indexOf(name))
  if (
    places->Array.someWithIndex((at, index) =>
      index > 0 && at <= places->Array.getUnsafe(index - 1)
    )
  ) {
    problems->Array.push(`sections stand out of order; the order is ${order->Array.join(", ")}`)
  }
  if !(known->Array.includes("Question")) {
    problems->Array.push("no `## Question`")
  }
  switch status {
  | Some("draft") if known->Array.includes("Decision") =>
    problems->Array.push("a draft has no `## Decision`; it is `accepted` once decided")
  | Some("draft") | None => ()
  | Some(_) if !(known->Array.includes("Decision")) => problems->Array.push("no `## Decision`")
  | Some(_) => ()
  }
  problems
}

/** A landed RFC names the commits it landed in, and no other names any. */
let checkStatus = (front: front) =>
  switch (front.status, front.commits) {
  | ("landed", []) => ["a landed RFC names at least one commit"]
  | ("landed", _) | (_, []) => []
  | (status, _) => [`a ${status} RFC landed nothing, so \`commits\` is empty`]
  }

/** Every place a body leaves plain Markdown, raw HTML or a line written as a directive. */
let checkPlain = body => {
  let problems = []
  let rec walk = (node: Markdown.node) => {
    if node.kind == "html" {
      let raw = node.value->Option.getOr("")->String.slice(~start=0, ~end=40)
      problems->Array.push(
        `raw HTML ${JSON.stringifyAny(raw)->Option.getOr("")}; an RFC is plain Markdown`,
      )
    }
    node.children->Option.getOr([])->Array.forEach(walk)
  }
  walk(Markdown.tree(body))
  body
  ->String.split("\n")
  ->Array.forEach(line =>
    if /^ {0,3}:{2,}[a-z]/->RegExp.test(line) {
      problems->Array.push(
        `directive ${JSON.stringifyAny(line->String.trim)->Option.getOr(
            "",
          )}; an RFC calls no component`,
      )
    }
  )
  problems
}
