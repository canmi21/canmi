open Testing

let statuses = Dict.fromArray([("aaaaa", "draft"), ("bbbbb", "landed"), ("ccccc", "accepted")])
let found = (text, ~rows=false) => Todos.problems(text, ~file="f.res", ~statuses, ~rows)

describe("a todo naming what is open", () => {
  test("passes a marker naming a draft RFC, in either language", () => {
    expect(found("let a = %todo(\"aaaaa\")\n"))->toEqual([])
    expect(found("\t\t\ttodo!(\"aaaaa\")\n"))->toEqual([])
  })

  test("names one naming an RFC that is closed, accepted or unknown", () => {
    expect(found("let a = %todo(\"bbbbb\")\n"))->toEqual([
      "f.res:1: waits on bbbbb, which is landed",
    ])
    expect(found("x\ntodo!(\"ccccc\")\n"))->toEqual(["f.res:2: waits on ccccc, which is accepted"])
    expect(found("todo!(\"zzzzz\")\n"))->toEqual([
      "f.res:1: waits on zzzzz, which no RFC of its id space holds",
    ])
  })

  test("names one naming nothing, and lets a checklist hold the row it names", () => {
    expect(found("let a = %todo()\n"))->toEqual(["f.res:1: a todo naming nothing"])
    expect(found("todo!()\n"))->toEqual(["f.res:1: a todo naming nothing"])
    expect(found("let a = %todo(\"C21\")\n", ~rows=true))->toEqual([])
  })

  test("reads a comment and a mention without a call as prose", () => {
    expect(found("says: \"A %todo or a todo! names a row\"\n"))->toEqual([])
    expect(found(" * implemented by the marker todo!(\"zzzzz\")\n"))->toEqual([])
  })
})
