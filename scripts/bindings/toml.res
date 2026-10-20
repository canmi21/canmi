/** smol-toml, which reads a TOML document as JSON-like values, a datetime as a Date. */
@module("smol-toml") external parse: string => JSON.t = "parse"

let isDate: JSON.t => bool = %raw(`value => value instanceof Date`)
