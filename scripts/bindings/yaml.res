/** The yaml package, which reads a YAML document as JSON-like values and throws where it cannot. */
@module("yaml") external parse: string => JSON.t = "parse"
