/**
 * What a repository's tooling and tests keep, over its tracked files. A soft rule warns until the
 * repositories that break it today are fixed.
 */
let soft = ["rust-nextest", "release-age", "ports-strict", "generated-marked"]

/** The findings that fail and those that warn, each of a repository's rules read once. */
let found = (~root): (array<string>, array<string>) => {
  let paths = Lines.tracked(root)
  let held = [
    ("release-age", Pinned.ages(~root, ~paths)),
    ("images-pinned", Pinned.bases(~root, ~paths)),
    ("ports-strict", Ports.servers(~root, ~paths)),
    ("test-port-zero", Ports.tests(~root, ~paths)),
    ("rust-nextest", Rust_tests.main(~root, ~paths)),
    ("generated-marked", Generated.main(~root, ~paths)),
  ]
  let say = ((rule, problems)) => problems->Array.map(problem => `${problem} (${rule})`)
  (
    held->Array.filter(((rule, _)) => !(soft->Array.includes(rule)))->Array.flatMap(say),
    held->Array.filter(((rule, _)) => soft->Array.includes(rule))->Array.flatMap(say),
  )
}
