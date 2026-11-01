/** Which changed files raise a package's patch, and which package each belongs to. */
let excludedDirectories = ["docs", "tests"]

/** The lint and format settings, and the prose beside the code, none of which it produces. */
let settings = [
  ".editorconfig",
  ".gitattributes",
  ".gitignore",
  ".oxfmtrc.json",
  ".oxlintrc.json",
  "actionlint.yaml",
  "clippy.toml",
  "deny.toml",
  "jujutsu.toml",
  "rustfmt.toml",
]

let isTest = /_test\.[^\/]+$/
let isProse = /(\.md|^LICENSE[^\/]*)$/

/** Whether a change to `path` counts by default, a comment alone counting as source. */
let counts = path => {
  let parts = path->String.split("/")
  let name = parts->Array.at(-1)->Option.getOr("")
  !(parts->Array.some(part => excludedDirectories->Array.includes(part))) &&
  !(settings->Array.includes(name)) &&
  !RegExp.test(isTest, name) &&
  !RegExp.test(isProse, name)
}

let under = (path, directory) =>
  directory == "" || path == directory || path->String.startsWith(directory ++ "/")

/** The deepest of `directories` holding `path`, the root being the empty one. */
let owner = (directories, path) =>
  directories
  ->Array.filter(directory => under(path, directory))
  ->Array.reduce("", (best, directory) =>
    directory->String.length > best->String.length ? directory : best
  )

let versionLine = /^version\s*=\s*"[^"]*"\r?\n/m

/** A Cargo.lock with each local crate's version taken out, those having no `source` line. */
let lockBare = text =>
  text
  ->String.split("[[package]]")
  ->Array.map(block =>
    block->String.includes("\nsource = ") ? block : block->String.replaceRegExp(versionLine, "")
  )
  ->Array.join("[[package]]")

/**
 * A file as a raise leaves no trace in it, so that a landing's own roll is no change of the file.
 * Every other file is itself.
 */
let bare = (path, text) =>
  switch path->String.split("/")->Array.at(-1) {
  | Some("Cargo.lock") => lockBare(text)
  | Some("Cargo.toml") => text->String.replaceRegExp(versionLine, "")
  | Some("package.json") => text->String.replaceRegExp(/^\s*"version":\s*"[^"]*",?\r?\n/m, "")
  | _ => text
  }

/** A file's lines as a `jj diff --summary` names them, each side of a rename apart. */
let summarized = line =>
  switch line->String.slice(~start=2) {
  | "" => []
  | path =>
    switch /^(.*)\{(.*) => (.*)\}(.*)$/->RegExp.exec(path) {
    | Some(found) =>
      switch found->RegExp.Result.matches->Array.map(part => part->Option.getOr("")) {
      | [before, from, to, after] => [
          `${before}${from}${after}`->String.replaceAll("//", "/"),
          `${before}${to}${after}`->String.replaceAll("//", "/"),
        ]
      | _ => [path]
      }
    | None => [path]
    }
  }
