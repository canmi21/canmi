/** As much of vitest as the scripts' tests call. */
@module("vitest") external describe: (string, unit => unit) => unit = "describe"
@module("vitest") external test: (string, unit => unit) => unit = "test"
@module("vitest") external beforeEach: (unit => unit) => unit = "beforeEach"
@module("vitest") external afterEach: (unit => unit) => unit = "afterEach"

type expectation<'a>
@module("vitest") external expect: 'a => expectation<'a> = "expect"
@send external toBe: (expectation<'a>, 'a) => unit = "toBe"
@send external toEqual: (expectation<'a>, 'a) => unit = "toEqual"
@send external toMatch: (expectation<string>, RegExp.t) => unit = "toMatch"
@send external toBeUndefined: expectation<'a> => unit = "toBeUndefined"

@module("node:os") external tmpdir: unit => string = "tmpdir"
@module("node:fs") external mkdtempSync: string => string = "mkdtempSync"
