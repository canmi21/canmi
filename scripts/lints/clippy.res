/**
 * A repository's `lint-rust`: clippy over the crates `RUST_PACKAGES` names, or all, denied under
 * `AUDIT`.
 */
let packages = Spawn.words(Node.env->Dict.get("RUST_PACKAGES"))

Spawn.exec(
  "cargo",
  [
    ["clippy"],
    packages->Array.length > 0 ? packages : ["--workspace"],
    ["--all-targets"],
    Node.envOn("AUDIT") ? ["--", "-D", "warnings"] : [],
  ]->Array.flat,
)
