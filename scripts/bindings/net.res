/**
 * Node's buffers, hashes, compression, file descriptors and HTTP, as the deploy scripts call them.
 */
type bytes = Node.bytes

@val @scope("Buffer") external alloc: int => bytes = "alloc"
@val @scope("Buffer") external fromText: (string, @as("utf8") _) => bytes = "from"
@val @scope("Buffer") external concat: array<bytes> => bytes = "concat"
@get external size: bytes => int = "length"
@send external subarray: (bytes, int, int) => bytes = "subarray"
@send external copy: (bytes, bytes, int) => int = "copy"
@send external writeUInt32: (bytes, float, int) => int = "writeUInt32LE"
@send external writeUInt16: (bytes, int, int) => int = "writeUInt16LE"
@send external text: (bytes, @as("utf8") _) => string = "toString"

type stats = {size: float, mode: int, mtime: Date.t}
@module("node:fs") external statSync: string => stats = "statSync"
@send external isDirectory: stats => bool = "isDirectory"
@send external isFile: stats => bool = "isFile"
@module("node:fs") external openSync: (string, string) => int = "openSync"
@module("node:fs") external readSync: (int, bytes) => int = "readSync"
@module("node:fs") external writeSync: (int, bytes) => int = "writeSync"
@module("node:fs") external closeSync: int => unit = "closeSync"
@module("node:fs") external rmFile: string => unit = "rmSync"

type readStream
@module("node:fs") external createReadStream: string => readStream = "createReadStream"

@module("node:zlib") external crc32: (bytes, float) => float = "crc32"
type deflation = {level: int}
@module("node:zlib") external deflateRawSync: (bytes, deflation) => bytes = "deflateRawSync"

type hash
@module("node:crypto") external createHash: string => hash = "createHash"
@send external updateText: (hash, string) => hash = "update"
@send external updateBytes: (hash, bytes) => hash = "update"
@send external hexDigest: (hash, @as("hex") _) => string = "digest"
@send external digestBytes: hash => bytes = "digest"
@module("node:crypto") external hmacText: (@as("sha256") _, string) => hash = "createHmac"
@module("node:crypto") external hmacBytes: (@as("sha256") _, bytes) => hash = "createHmac"

type url
@new external url: string => url = "URL"
@get external host: url => string = "host"
@get external hostname: url => string = "hostname"
@get external port: url => string = "port"
@get external protocol: url => string = "protocol"
@get external pathname: url => string = "pathname"
@get external search: url => string = "search"
@get external searchParams: url => Dict.t<string> = "searchParams"

type params
@new external params: Dict.t<string> => params = "URLSearchParams"
@send external paramsText: params => string = "toString"
@val @scope("Object") external fromEntries: 'a => Dict.t<string> = "fromEntries"

type requestOptions = {
  method: string,
  host: string,
  port: string,
  path: string,
  headers: Dict.t<string>,
  timeout: int,
}
type clientRequest
type incoming
@module("node:http")
external httpRequest: (requestOptions, incoming => unit) => clientRequest = "request"
@module("node:https")
external httpsRequest: (requestOptions, incoming => unit) => clientRequest = "request"
@send external onRequestError: (clientRequest, @as("error") _, JsExn.t => unit) => unit = "on"
@send external onTimeout: (clientRequest, @as("timeout") _, unit => unit) => unit = "on"
@send external destroy: (clientRequest, JsExn.t) => unit = "destroy"
@send external endEmpty: clientRequest => unit = "end"
@send external endWith: (clientRequest, bytes) => unit = "end"
@send external onStreamError: (readStream, @as("error") _, JsExn.t => unit) => readStream = "on"
@send external pipe: (readStream, clientRequest) => unit = "pipe"
@get external statusCode: incoming => Nullable.t<int> = "statusCode"
@send external onData: (incoming, @as("data") _, bytes => unit) => unit = "on"
@send external onEnd: (incoming, @as("end") _, unit => unit) => unit = "on"
@send external onIncomingError: (incoming, @as("error") _, JsExn.t => unit) => unit = "on"

/** A JavaScript Error carrying `message`. */
@new external error: string => JsExn.t = "Error"

/** A file's bytes, or None where it cannot be read. */
let readBytesOf = path =>
  try Some(Node.readBytes(path)) catch {
  | _ => None
  }
