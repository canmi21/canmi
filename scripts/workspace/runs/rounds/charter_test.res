open Testing

let text = "# Charter\n\nTarget test, in steps:\n\n1. Roll by commit. Two sentences.\n   after: none\n2. Faults.\n   after: 1\n3a. One line.\n   after: 2\n3b. Beside it.\n   after: 2\n4. Last.\n   after: 3a, 3b\n"

let green = (step, at) => Figures.Green({step, at})

describe("a charter's steps", () => {
  test("are read with what each comes after", () => {
    expect(Charter.stepsOf(text))->toEqual([
      {id: "1", after: []},
      {id: "2", after: ["1"]},
      {id: "3a", after: ["2"]},
      {id: "3b", after: ["2"]},
      {id: "4", after: ["3a", "3b"]},
    ])
  })

  test("an older charter, with no `after`, has none", () => {
    expect(Charter.stepsOf("1. Roll by commit.\n2. Faults.\n"))->toEqual([])
  })

  test("says each reference that does not resolve, rather than going silent", () => {
    let said = (text, ~greens=[]) => Charter.problemsOf(text, ~greens)
    expect(said(text))->toEqual([])
    [
      "1. x\n   after: none\n2. y\n   after: 1,\n",
      "1. x\n   after: none\n2. y\n   after: None\n",
      "1. x\n   after: none\n2. y\n   after: 1 and 2\n",
      "1. x\n   after: none\n2. y\n   after: 9\n",
      "1. x after: none\n2. y\n   after: 1\n",
      "1. x\n2. y\n",
    ]->Array.forEach(written => expect((written, said(written) != []))->toEqual((written, true)))
    expect(said("1. x\nafter: none\n"))->toEqual([])
    expect(said("1. x\n   after: none\n", ~greens=["step-1"]))->toEqual([
      "green names step step-1, which is no step",
    ])
  })

  test("the template's own charter is of this shape", () => {
    let (_, written) = Thread.shape->Array.getUnsafe(0)
    expect(Charter.stepsOf(written)->Array.map(step => step.id))->toEqual(["1", "2"])
  })

  let ids = (records, ~at) =>
    Charter.ready(Charter.stepsOf(text), records, ~at)->Array.map(((step, since)) => (
      step.id,
      since,
    ))

  test("are ready once all they come after are green, side by side", () => {
    expect(ids([], ~at=5.))->toEqual([("1", 0.)])
    expect(ids([green("1", 10.)], ~at=15.))->toEqual([("2", 10.)])
    expect(ids([green("1", 10.), green("2", 20.)], ~at=25.))->toEqual([("3a", 20.), ("3b", 20.)])
    expect(ids([green("1", 10.), green("2", 20.), green("3a", 30.)], ~at=35.))->toEqual([
      ("3b", 20.),
    ])
  })

  test("read as of a time, a later green unseen, and a step green twice counted once", () => {
    let records = [green("1", 10.), green("1", 40.), green("2", 20.)]
    expect(ids(records, ~at=15.))->toEqual([("2", 10.)])
    expect(ids(records, ~at=50.))->toEqual([("3a", 20.), ("3b", 20.)])
  })
})
