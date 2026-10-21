/** A repository's `lint`, oxlint over what it is given, its warnings failing under `AUDIT`. */
Spawn.exec("oxlint", Array.concat(Node.args(), Node.envOn("AUDIT") ? ["--deny-warnings"] : []))
