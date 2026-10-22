/**
 * Every host, mail address and IP address an RFC writes that could be somebody else's, since
 * everything in one is published. RFC 2ut6h.
 */
/** Names RFC 2606 reserves so they never resolve, the same set the refs gate exempts. */
let reserved = /^(?:[a-z0-9-]+\.)*(?:test|example|invalid|localhost|example\.(?:com|net|org))$/i

/** RFC 5737's documentation ranges, the only addresses an example may give. */
let documentation = /^(?:192\.0\.2|198\.51\.100|203\.0\.113)\.\d{1,3}$/

/** A file's extension, which ends a name as a top-level domain would and is not one here. */
let extensions = "md mdx ts js mjs cjs json jsonc yaml yml toml svelte css html rs py sh txt lock png svg avif webp jpg ico woff2 stylex env sql go mp4 webm vtt res"->String.split(
  " ",
)

/** The author's own public names and the hosts under them, written as hosts and never as mail. */
let own = /^(?:[a-z0-9-]+\.)*(?:canmi\.(?:net|app|icu)|monoflake\.(?:com|net)|ffoni\.com|ixc\.one|ill\.li|symlink\.si)$/i

/** Top-level domains a name in code ends with when it is a host rather than a call or a token. */
let hostlike = "com net org io dev app co ai me sh so one li si icu cloud xyz info biz us uk de fr jp cn tv cc gg"->String.split(
  " ",
)

let allowed = host => reserved->RegExp.test(host) || own->RegExp.test(host)

/** Each match of a global `pattern` in `text`, by its groups, the whole match first. */
let all = (pattern: RegExp.t, text): array<array<string>> => {
  let found = []
  let going = ref(true)
  while going.contents {
    switch pattern->RegExp.exec(text) {
    | Some(result) =>
      found->Array.push(
        Array.concat(
          [result->RegExp.Result.fullMatch],
          result->RegExp.Result.matches->Array.map(group => group->Option.getOr("")),
        ),
      )
      if result->RegExp.Result.fullMatch == "" {
        pattern->RegExp.setLastIndex(pattern->RegExp.lastIndex + 1)
      }
    | None => going := false
    }
  }
  found
}

let group = (found: array<string>, at) => found->Array.get(at)->Option.getOr("")

let tldOf = name => name->String.slice(~start=name->String.lastIndexOf(".") + 1)->String.toLowerCase

let check = (text): array<string> => {
  let problems = []
  let seen = []
  let flag = (what, value) =>
    if !(seen->Array.includes(value)) {
      seen->Array.push(value)
      problems->Array.push(
        `${what} ${value} could be real; write a reserved one, as in example.com`,
      )
    }
  all(/[a-z][a-z0-9+.-]*:\/\/([^\/\s:?#)\]>`'"]+)/gi, text)->Array.forEach(found => {
    let host = group(found, 1)
    if !allowed(host) && !(documentation->RegExp.test(host)) {
      flag("host", host)
    }
  })
  all(/[\w.+-]+@((?:[a-z0-9-]+\.)+[a-z]{2,63})\b/gi, text)->Array.forEach(found => {
    let domain = group(found, 1)
    if !(reserved->RegExp.test(domain)) {
      flag("mail domain", domain)
    }
  })
  // In code a dotted name is a call or a token unless it ends as a host commonly does.
  let code = () => /^ {0,3}(```|~~~)[\s\S]*?^ {0,3}\1|`(?:[^`\n]|\n(?![ \t]*\n))*`/gm
  let prose = text->String.replaceRegExp(code(), " ")
  let coded = all(code(), text)->Array.map(found => group(found, 0))->Array.join("\n")
  let names = within =>
    all(/(?<![\w@\/.:-])(?:[a-z0-9-]+\.)+[a-z]{2,63}(?![\w-])/gi, within)->Array.map(found =>
      group(found, 0)
    )
  names(prose)->Array.forEach(name =>
    if !(extensions->Array.includes(tldOf(name))) && !allowed(name) {
      flag("host", name)
    }
  )
  names(coded)->Array.forEach(name =>
    if hostlike->Array.includes(tldOf(name)) && !allowed(name) {
      flag("host", name)
    }
  )
  all(/(?<![\w.])\d{1,3}(?:\.\d{1,3}){3}(?![\w.])/g, text)->Array.forEach(found => {
    let address = group(found, 0)
    if !(documentation->RegExp.test(address)) {
      flag("address", address)
    }
  })
  problems
}
