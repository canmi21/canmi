/** The addresses and domains a test writes, `test-documentation-values` in toolchain.res. */
let fixture = /(?:^|\/)(?:fixtures?|__fixtures__|testdata)\//
let address = /(?<![\w.-])(?:\d{1,3}\.){3}\d{1,3}(?![\w-]|\.\d)/g
/** The suffixes of a domain, none that code or a bundle name carries, as `.dev` and `.app`. */
let domain = /(?<![\w.@-])(?:[a-z0-9-]+\.)+(?:com|net|org|io|cloud|xyz|info)(?![\w-])/gi
let skippedKinds = [".lock", ".svg", ".png", ".jpg", ".ico", ".woff2", ".map"]

/** An IPv4 address as one number, none where an octet is past 255. */
let number = (text): option<float> => {
  let octets = text->String.split(".")->Array.filterMap(Float.fromString)
  octets->Array.length == 4 && octets->Array.every(octet => octet <= 255.0)
    ? Some(octets->Array.reduce(0.0, (sum, octet) => sum *. 256.0 +. octet))
    : None
}

/** Whether `text` lies in the IPv4 block `cidr`, written address and prefix length. */
let inside = (text, ~cidr) =>
  switch (cidr->String.split("/"), number(text)) {
  | ([base, length], Some(found)) =>
    switch (number(base), Int.fromString(length)) {
    | (Some(start), Some(bits)) =>
      let size = Math.pow(2.0, ~exp=Int.toFloat(32 - bits))
      Math.floor(found /. size) == Math.floor(start /. size)
    | _ => false
    }
  | _ => false
  }

/** The documentation blocks, the private one a test may use, loopback and the unspecified one. */
let blocks = () =>
  Array.concat(Toolchain.documentation["addresses"], Toolchain.documentation["allowed"])
  ->Array.filter(block => !(block->String.includes(":")))
  ->Array.concat(["127.0.0.0/8", "0.0.0.0/8", "255.0.0.0/8"])

/** Whether `host` is a documentation domain or sits under one. */
let documented = host => {
  let lower = host->String.toLowerCase
  Toolchain.documentation["domains"]
  ->Array.concat(Toolchain.publicDomains)
  ->Array.some(name =>
    name->String.startsWith(".")
      ? lower->String.endsWith(name)
      : lower == name || lower->String.endsWith("." ++ name)
  )
}

/** Each address and domain a line writes that `documentation` does not hold. */
let outside = line => {
  let spelled = pattern => References.each(pattern, line)->Array.map(found => found.whole)
  Array.concat(
    spelled(address)->Array.filter(found =>
      number(found)->Option.isSome && !(blocks()->Array.some(cidr => inside(found, ~cidr)))
    ),
    spelled(domain)->Array.filter(host => !documented(host)),
  )
}

/** The line, counted from zero, a test or fixture file is read from, none for any other file. */
let from = (path, text) =>
  if skippedKinds->Array.includes(Node.extname(path)) || Node.extname(path) == "" {
    None
  } else if (
    [fixture, Ports.directory, Ports.named]->Array.some(pattern => pattern->RegExp.test(path))
  ) {
    Some(0)
  } else if path->String.endsWith(".rs") {
    ["#[cfg(test)]", "#[test]"]
    ->Array.map(mark => text->String.indexOf(mark))
    ->Array.filter(at => at >= 0)
    ->Array.toSorted((a, b) => Int.toFloat(a - b))
    ->Array.get(0)
    ->Option.map(at => text->String.slice(~start=0, ~end=at)->String.split("\n")->Array.length - 1)
  } else {
    None
  }

/** Each address or domain outside `documentation` in one file's text, by `file:line`. */
let problems = (text, ~file): array<string> =>
  switch from(file, text) {
  | None => []
  | Some(first) =>
    text
    ->String.split("\n")
    ->Array.mapWithIndex((line, index) =>
      index < first
        ? []
        : outside(line)->Array.map(found =>
            `${file}:${Int.toString(index + 1)}: a test writes ${found}, outside documentation`
          )
    )
    ->Array.flat
  }

/** Each address or domain outside `documentation` in the tests and fixtures among `paths`. */
let main = (~root, ~paths: array<string>): array<string> =>
  paths
  ->Array.filter(path => !Pinned.vendored(path))
  ->Array.flatMap(path => problems(References.read(Node.join([root, path])), ~file=path))
