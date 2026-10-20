/** The workspace's own text against model/rules/voice.res, and toolchain.res on loopback. */
/** The files that state a rule's words, and so quote them. */
let stating = ["model/rules/voice.res", "model/checks/words.res"]
let binary = [".png", ".jpg", ".ico", ".woff2"]
let skipped = ["pnpm-lock.yaml", "LICENSE"]

/** A line with its inline code blanked: a word in backticks is an example, not a use. */
let inlineCode = /`[^`\n]+`/g
let plain = line => line->String.replaceRegExp(inlineCode, "``")

let british =
  Voice.british->Array.map(((word, american)) => (
    RegExp.fromString(`\\b${word}\\w*`, ~flags="i"),
    word,
    american,
  ))
let shortened =
  Voice.shortened->Array.map(((short, whole)) => (
    RegExp.fromString(`\\b${short}\\b`),
    short,
    whole,
  ))

let main = (~root): array<string> =>
  References.tracked(root, ~skipFiles=skipped)
  ->Array.filter(path => !(binary->Array.includes(Node.extname(path))))
  ->Array.flatMap(path => {
    let relative = Node.relative(root, path)
    let quoting = Voice.quoting->Array.includes(relative) || stating->Array.includes(relative)
    References.read(path)
    ->String.split("\n")
    ->Array.mapWithIndex((line, index) => (index + 1, plain(line)))
    ->Array.flatMap(((number, line)) => {
      let at = `${relative}:${Int.toString(number)}`
      let found = []
      if !quoting && Voice.foreign->RegExp.test(line) {
        found->Array.push(`${at}: text outside English`)
      }
      if !quoting {
        british->Array.forEach(
          ((pattern, word, american)) =>
            if pattern->RegExp.test(line) {
              found->Array.push(`${at}: ${word} is British; write ${american}`)
            },
        )
        shortened->Array.forEach(
          ((pattern, short, whole)) =>
            if pattern->RegExp.test(line) {
              found->Array.push(`${at}: ${short} is shorthand; write ${whole}`)
            },
        )
      }
      if Toolchain.loopback->RegExp.test(line) {
        found->Array.push(`${at}: a literal loopback address; write localhost`)
      }
      found
    })
  })
