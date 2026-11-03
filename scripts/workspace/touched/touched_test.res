open Testing

let blocks = [("storage", "code/products/storage"), ("host", "code/products/host")]
let touched = paths => Touched.of_(~paths, ~blocks, ~full=false)

describe("the blocks a change touches", () => {
  test("is every block when asked for full", () => {
    expect(Touched.of_(~paths=["code/products/host/a.rs"], ~blocks, ~full=true))->toEqual(
      Touched.Every,
    )
  })
  test("is every block for an empty change", () => {
    expect(touched([]))->toEqual(Touched.Every)
  })
  test("names the block holding one file", () => {
    expect(touched(["code/products/host/src/a.rs"]))->toEqual(Touched.Blocks(["host"]))
  })
  test("names two blocks once each in the order given", () => {
    let paths = ["code/products/host/a.rs", "code/products/storage/b.rs", "code/products/host/c.rs"]
    expect(touched(paths))->toEqual(Touched.Blocks(["storage", "host"]))
  })
  test("is every block for a path in no block's directory", () => {
    expect(touched(["code/products/host/a.rs", "model/x.res"]))->toEqual(Touched.Every)
  })
  test("does not count a directory that only begins like a block's", () => {
    expect(touched(["code/products/storagex/a.rs"]))->toEqual(Touched.Every)
    expect(touched(["code/products/storage"]))->toEqual(Touched.Every)
  })
})
