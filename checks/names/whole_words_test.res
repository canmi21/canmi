open Testing

let problems = (~file="source.rs", text) => Whole_words.problems(text, ~file)

describe("whole identifier words", () => {
  test("splits underscores, camel case and acronym boundaries", () => {
    ["dbPath", "db_path", "DBPool"]->Array.forEach(
      identifier => {
        expect(problems(identifier))->toEqual([
          `source.rs:1: ${identifier} holds db, written database`,
        ])
      },
    )
  })

  test("leaves whole words and the model's omitted spellings alone", () => {
    expect(problems("dbase valid srcs process cfg len sql str fn ref var buf repo"))->toEqual([])
  })

  test("ignores comments and string literals while preserving line numbers", () => {
    expect(problems("// db\n/* db\nconn */\n\"db\"; let db = 1;\nconn: Connection"))->toEqual([
      "source.rs:4: db holds db, written database",
      "source.rs:5: conn holds conn, written connection",
    ])
    expect(problems(~file="source.py", "# db\n'''conn\ndb'''\n\"db\""))->toEqual([])
    expect(problems(~file="source.ts", "'db'; `conn`; \"db\\\"conn\""))->toEqual([])
  })

  test("exempts member uses after a dot or namespace separator", () => {
    expect(
      problems("value.len(); value.db; value . /* gap */ conn; Type::err; Type:: db"),
    )->toEqual([])
  })

  test("reports bindings and field declarations on their original lines", () => {
    expect(problems("\nlet db = 1;\nstruct Pool {\n conn: Connection\n}"))->toEqual([
      "source.rs:2: db holds db, written database",
      "source.rs:4: conn holds conn, written connection",
    ])
  })

  test("keeps scanning after Rust lifetimes and character literals", () => {
    expect(problems("let value: &'a Database = db; 'x'; let conn = value;"))->toEqual([
      "source.rs:1: db holds db, written database",
      "source.rs:1: conn holds conn, written connection",
    ])
  })

  test("exempts the capitalized Rust Err variant alone", () => {
    expect(problems("Err(error); let err = error;"))->toEqual([
      "source.rs:1: err holds err, written error",
    ])
    expect(problems(~file="source.ts", "Err(error)"))->toEqual([
      "source.ts:1: Err holds err, written error",
    ])
  })

  test("exempts Rust attribute words including nested brackets", () => {
    expect(problems("#[db(conn = [req, resp], note = \"]\")]\n#![ctx]\nlet db = 1;"))->toEqual([
      "source.rs:3: db holds db, written database",
    ])
  })

  test("a decorator, a Rust macro and a library's own spelling are exempt", () => {
    let held = (text, ~file) => Whole_words.problems(text, ~file)
    expect(held("@val external now: unit => int = \"now\"\n", ~file="a.res"))->toEqual([])
    expect(held("let x = params![1];\nlet y: SocketAddr = z;\n", ~file="a.rs"))->toEqual([])
    expect(held("let a: DbConfig = b; params_from_iter(c);\n", ~file="a.rs"))->toEqual([])
    expect(held("let params = 1;\n", ~file="a.rs")->Array.length)->toEqual(1)
  })
})
