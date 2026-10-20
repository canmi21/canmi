open Testing

let rust = `//! The crate.

/// A greeting, said once.
pub fn greet<'a>(name: &'a str, times: u8) -> String {
	// Said as many times as asked.
	let line = format!("hello, {name} // not a comment /* nor this */");
	let raw = r#"a "quoted" // word"#;
	let quote = '\\'';
	let brace = '{';
	/* a block /* nested */ still a comment */
	'outer: for _ in 0..times {
		break 'outer;
	}
	match times {
		0 => String::new(),
		_ => { line.repeat(times as usize) },
	}
}
`

// The source as rustfmt might lay it out, its comments rewritten and the optional commas moved.
let reflowed = `/*! The crate, said otherwise. */

/** A greeting. */
pub fn greet<'a>(
	name: &'a str,
	times: u8,
) -> String {
	let line =
		format!("hello, {name} // not a comment /* nor this */",);
	let raw = r#"a "quoted" // word"#;
	let quote = '\\'';
	let brace = '{';
	'outer: for _ in 0..times { break 'outer; }
	match times {
		0 => String::new(),
		_ => {
			line.repeat(times as usize)
		}
	}
}
`

let same = (path, before, after) => Fingerprint.same(path, Some(before), Some(after))

describe("Rust", () => {
  test("comments and layout are no change", () =>
    expect(same("src/lib.rs", rust, reflowed))->toBe(true)
  )

  test("a changed token is a change", () => {
    expect(same("src/lib.rs", rust, rust->String.replace("0..times", "1..times")))->toBe(false)
    expect(same("src/lib.rs", rust, rust->String.replace("u8", "u16")))->toBe(false)
  })

  test("a change inside a literal is a change however it looks", () => {
    expect(
      same("src/lib.rs", rust, rust->String.replace("// not a comment", "//  not a comment")),
    )->toBe(false)
    expect(same("src/lib.rs", rust, rust->String.replace("// word\"#", "//word\"#")))->toBe(false)
    expect(same("src/lib.rs", rust, rust->String.replace("'{'", "'}'")))->toBe(false)
  })

  test("literals and lifetimes are tokens of their own", () => {
    let tokens = Fingerprint.rustTokens(
      "x = b'a' + '\\n'; fn f<'a>() -> &'a [u8] { br##\"x\"# y\"## }",
    )
    expect(tokens)->toContain("b'a'")
    expect(tokens)->toContain("'\\n'")
    expect(tokens)->toContain("'a")
    expect(tokens)->toContain("br##\"x\"# y\"##")
    expect(Fingerprint.rustTokens("r#type c\"s\""))->toEqual(["r#type", "c\"s\""])
  })

  test("a tuple of one keeps its comma", () => {
    expect(same("a.rs", "let x = (1,);", "let x = (1);"))->toBe(false)
    expect(same("a.rs", "f(1, 2,);", "f(1, 2);"))->toBe(true)
    expect(same("a.rs", "let v = [1, 2,];", "let v = [1, 2];"))->toBe(true)
    expect(same("a.rs", "format!(\"x\",); f::<u8>(a,)", "format!(\"x\"); f::<u8>(a)"))->toBe(true)
    expect(same("a.rs", "Some((x,))", "Some((x))"))->toBe(false)
    expect(same("a.rs", "return (x,);", "return (x);"))->toBe(false)
  })

  test("punctuation is one character a token", () => {
    expect(same("a.rs", "if a&&b {}", "if a && b {}"))->toBe(true)
    expect(same("a.rs", "a + b", "a - b"))->toBe(false)
  })

  test("an unfinished source is read to its end", () => {
    expect(Fingerprint.rustTokens("let s = \"open"))->toEqual(["let", "s", "=", "\"open"])
    expect(Fingerprint.rustTokens("x /* open"))->toEqual(["x"])
  })
})

describe("lines", () => {
  let dockerfile = "# syntax=docker/dockerfile:1\n# check=skip=X\n# A comment.\nFROM a\n\n\tRUN b \\\n\t# inside\n\t\tc\n"

  test("a Dockerfile's comments and blank lines are no change", () => {
    let edited =
      dockerfile
      ->String.replace("# A comment.", "# Another.\n\n")
      ->String.replace("# inside", "# else")
    expect(same("apps/x/y/Dockerfile", dockerfile, edited))->toBe(true)
  })

  test("a directive is not a comment", () => {
    expect(
      same("apps/x/y/Dockerfile", dockerfile, dockerfile->String.replace("# check=skip=X\n", "")),
    )->toBe(false)
    expect(
      same("apps/x/y/Dockerfile", dockerfile, dockerfile->String.replace("RUN b", "RUN d")),
    )->toBe(false)
  })

  test("a heredoc is read as written", () => {
    let before = "FROM a\nCOPY <<EOF /etc/x\n# kept\nEOF\n# dropped\n"
    expect(same("Dockerfile", before, before->String.replace("# dropped", "# gone")))->toBe(true)
    expect(same("Dockerfile", before, before->String.replace("# kept", "# changed")))->toBe(false)
  })

  test("the image task and the ignore file drop their comments", () => {
    let task = "#!/usr/bin/env bash\n# Why.\nset -e\n\nbuild # a note\n"
    expect(same(".mise/tasks/image", task, task->String.replace("# Why.", "# Because.")))->toBe(
      true,
    )
    expect(same(".mise/tasks/image", task, task->String.replace("bash", "sh")))->toBe(false)
    expect(same(".mise/tasks/image", task, task->String.replace("# a note", "# another")))->toBe(
      false,
    )
    expect(same(".dockerignore", "# Out.\n**/target\n", "**/target\n\n"))->toBe(true)
  })

  test("any other file is its bytes", () => {
    expect(same("apps/x/y/checks.toml", "a = 1\n", "a = 1 # one\n"))->toBe(false)
    expect(same("apps/x/y/run.sh", "# a\nx\n", "# b\nx\n"))->toBe(false)
  })
})

describe("TOML", () => {
  test("a declaration is its value", () => {
    let before = "name = \"geo\" # the app\n[container]\nport = 1\n"
    let commented = "# Geo.\nname = \"geo\"\n\n[container]\nport = 1\n"
    expect(same("apps/x/geo/service.toml", before, commented))->toBe(true)
    expect(
      same("apps/x/geo/service.toml", before, before->String.replace("port = 1", "port = 2")),
    )->toBe(false)
    expect(
      same("libs/a/Cargo.toml", "[package]\nname = \"a\"\n", "[package]\n# A.\nname = \"a\"\n"),
    )->toBe(true)
  })

  test("a file that appears or goes is a change", () => {
    expect(Fingerprint.same("a.rs", None, Some("fn f() {}")))->toBe(false)
    expect(Fingerprint.same("a.rs", Some("fn f() {}"), None))->toBe(false)
    expect(Fingerprint.same("a.rs", None, None))->toBe(true)
  })
})

describe("ignored", () =>
  test("prose, licenses and what a crate builds for its tests go into no image", () => {
    let crateDirectories = ["apps/data/primary", "libs/deploy"]
    [
      "README.md",
      "apps/data/primary/README.md",
      "LICENSE",
      "libs/deploy/LICENSE-MIT",
      "apps/data/primary/tests/one.rs",
      "libs/deploy/benches/b.rs",
      "libs/deploy/examples/e.rs",
    ]->Array.forEach(
      path => expectAs(Fingerprint.ignored(path, ~crateDirectories), path)->toBe(true),
    )
    [
      "apps/data/primary/src/tests.rs",
      "libs/deploy/src/tests/mod.rs",
      "apps/data/primary/tests",
    ]->Array.forEach(
      path => expectAs(Fingerprint.ignored(path, ~crateDirectories), path)->toBe(false),
    )
    expect(Fingerprint.ignored("apps/x/tests/a.rs", ~crateDirectories))->toBe(false)
  })
)
