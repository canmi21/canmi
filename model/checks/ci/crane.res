/** The ci-crane rule, docs/ci.md, over a repository's Nix files. */
let builders = ["buildRustPackage", "makeRustPlatform"]

/** What a Nix file's text builds Rust with that is not crane, once for the file. */
let problems = (text, ~file): array<string> =>
  builders
  ->Array.filter(builder => text->String.includes(builder))
  ->Array.map(builder => `${file}: builds Rust with ${builder}, which is not crane`)

let main = (~root): array<string> =>
  Lines.tracked(root)
  ->Array.filter(path => path->String.endsWith(".nix"))
  ->Array.flatMap(path => problems(Node.readFileSync(Node.join([root, path])), ~file=path))
