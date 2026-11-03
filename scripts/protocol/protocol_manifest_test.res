@module("vitest") external test: (string, unit => unit) => unit = "test"
@module("node:assert/strict") external equal: ('a, 'a) => unit = "deepStrictEqual"

let specs = Protocol_manifest.parse(`{"specs": [
    {"name": "first", "module": "first.tla", "quick": "first.cfg"},
    {"name": "second", "module": "second.tla", "quick": "second.cfg"},
    {"name": "third", "module": "third.tla", "quick": "third.cfg"}
  ]}`)

test("chosen keeps manifest order when no specs are named", () => {
  equal(Protocol_manifest.chosen(specs, []), specs)
})

test("chosen runs only the two named specs in argument order", () => {
  equal(
    Protocol_manifest.chosen(specs, ["third", "first"]),
    [specs->Array.getUnsafe(2), specs->Array.getUnsafe(0)],
  )
})

test("chosen refuses an unknown spec with the manifest names", () => {
  let refusal = try {
    ignore(Protocol_manifest.chosen(specs, ["missing"]))
    None
  } catch {
  | Protocol_manifest.Refused(message) => Some(message)
  }
  equal(refusal, Some("unknown spec missing, expected one of first, second, third"))
})
