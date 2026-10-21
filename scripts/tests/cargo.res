/** A repository's `test-rust`, the tests of the crates `RUST_PACKAGES` names, or all. */
let packages = Spawn.words(Node.env->Dict.get("RUST_PACKAGES"))

Spawn.exec("cargo", Array.concat(["test"], packages->Array.length > 0 ? packages : ["--workspace"]))
