open Testing

let holder: Advisor.holder = {name: "a", pid: 7, since: "t", handingTo: None}
let standing = (record, ~pid=1, ~alive=_ => true) => Advisor.standingOf(record, ~pid, ~alive)

describe("the advisor's seat", () => {
  test("tells the three cases and its own", () => {
    expect(standing(None))->toEqual(First)
    expect(standing(Some(holder)))->toEqual(Candidate(holder))
    expect(standing(Some(holder), ~alive=_ => false))->toEqual(Orphan(holder))
    expect(standing(Some(holder), ~pid=7))->toEqual(Holding(holder))
  })

  test("acts on the holder's order alone", () => {
    expect(Advisor.orderFrom(Some(holder), ~sender="a"))->toEqual(Ok())
    expect(Advisor.orderFrom(Some(holder), ~sender="b")->Result.isError)->toEqual(true)
    expect(Advisor.orderFrom(None, ~sender="b")->Result.isError)->toEqual(true)
  })

  test("reads its record and refuses a broken one as no record", () => {
    let text = Ledger.line([("name", JSON.String("a")), ("pid", JSON.Number(7.))])
    expect(Advisor.parse(text)->Option.map(one => one.pid))->toEqual(Some(7))
    expect(Advisor.parse("broken"))->toEqual(None)
  })
})
