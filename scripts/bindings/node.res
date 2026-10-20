/** Node's own modules, as much of them as the task scripts call. */
type spawnOptions = {
  stdio?: string,
  cwd?: string,
  encoding?: string,
  maxBuffer?: int,
  input?: string,
  timeout?: int,
}

type spawned = {
  status: Nullable.t<int>,
  error: Nullable.t<JsExn.t>,
  stdout: Nullable.t<string>,
  stderr: Nullable.t<string>,
}

@module("node:child_process")
external spawnSync: (string, array<string>, spawnOptions) => spawned = "spawnSync"
@module("node:child_process")
external execFileSync: (string, array<string>, spawnOptions) => string = "execFileSync"

@val external argv: array<string> = "process.argv"
@val external env: Dict.t<string> = "process.env"
@val external exit: int => 'a = "process.exit"
@val external cwd: unit => string = "process.cwd"
@val external isMain: bool = "import.meta.main"
@val external importMetaUrl: string = "import.meta.url"

/** The arguments a script was given, past node and the script. */
let args = () => argv->Array.slice(~start=2)

/** Whether `name` is set in the environment to something, as JavaScript reads a string as true. */
let envOn = name => env->Dict.get(name)->Option.mapOr(false, value => value != "")

/** Whether `name` is set in the environment to exactly `value`. */
let envIs = (name, value) => env->Dict.get(name) == Some(value)

type dirent
@get external name: dirent => string = "name"
@send external isDirectory: dirent => bool = "isDirectory"
@send external isFile: dirent => bool = "isFile"
@send external isSymbolicLink: dirent => bool = "isSymbolicLink"

type stats
@send external statsIsFile: stats => bool = "isFile"
@send external statsIsDirectory: stats => bool = "isDirectory"
@send external statsIsSymbolicLink: stats => bool = "isSymbolicLink"

type withTypes = {withFileTypes: bool}
type noThrow = {throwIfNoEntry: bool}
type removal = {recursive: bool, force: bool}

@module("node:fs") external existsSync: string => bool = "existsSync"
@module("node:fs") external readFileSync: (string, @as("utf8") _) => string = "readFileSync"
@module("node:fs") external readStdin: (@as(0) _, @as("utf8") _) => string = "readFileSync"
@module("node:fs") external writeFileSync: (string, string) => unit = "writeFileSync"
@module("node:fs") external readdir: string => array<string> = "readdirSync"
@module("node:fs") external readdirTyped: (string, withTypes) => array<dirent> = "readdirSync"
@module("node:fs") external statMaybe: (string, noThrow) => Nullable.t<stats> = "statSync"
@module("node:fs") external lstatSync: string => stats = "lstatSync"
@module("node:fs") external rmSync: (string, removal) => unit = "rmSync"
@module("node:fs") external realpathSync: string => string = "realpathSync"

/** The directory entries of `directory`, each with its type. */
let entries = directory => readdirTyped(directory, {withFileTypes: true})

/** What `path` is, or None where nothing is there. */
let stat = path => statMaybe(path, {throwIfNoEntry: false})->Nullable.toOption

@module("node:path") @variadic external join: array<string> => string = "join"
@module("node:path") @variadic external resolve: array<string> => string = "resolve"
@module("node:path") external relative: (string, string) => string = "relative"
@module("node:path") external dirname: string => string = "dirname"
@module("node:path") external basename: string => string = "basename"
@module("node:path") external sep: string = "sep"

@module("node:url") external fileURLToPath: string => string = "fileURLToPath"
@module("node:url") external pathToFileURL: string => {"href": string} = "pathToFileURL"

/** A command's output as it arrives, and its status, 1 where it gave none. */
let run = (~cwd=?, command, commandArgs) =>
  spawnSync(command, commandArgs, {stdio: "inherit", ?cwd}).status->Nullable.getOr(1)

/** What a command wrote to stdout, as text, or nothing where it wrote none. */
let output = (~cwd=?, command, commandArgs) =>
  spawnSync(
    command,
    commandArgs,
    {?cwd, encoding: "utf8", maxBuffer: 268435456},
  ).stdout->Nullable.getOr("")

@module("node:path") external isAbsolute: string => bool = "isAbsolute"

/** A string's characters by code point, as `[...text]` spreads it. */
@scope("Array") @val external codePoints: string => array<string> = "from"

type bytes
@module("node:fs") external readBytes: string => bytes = "readFileSync"
type decoder
type decoderOptions = {fatal: bool, ignoreBOM: bool}
@new external textDecoder: (string, decoderOptions) => decoder = "TextDecoder"
@send external decode: (decoder, bytes) => string = "decode"

@module("node:path") external extname: string => string = "extname"
@module("node:os") external tmpdir: unit => string = "tmpdir"
@module("node:fs") external mkdtempSync: string => string = "mkdtempSync"
@module("node:util") external isDeepStrictEqual: ('a, 'a) => bool = "isDeepStrictEqual"
@val external onExit: (@as("exit") _, unit => unit) => unit = "process.on"

type bytesOptions = {cwd?: string, maxBuffer?: int, input?: bytes}
@module("node:child_process")
external execBytes: (string, array<string>, bytesOptions) => bytes = "execFileSync"

/** The environment, as a copy a child process may be given. */
@val external envCopy: (@as(json`{}`) _, Dict.t<string>) => Dict.t<string> = "Object.assign"
type envOptions = {cwd?: string, env?: Dict.t<string>, stdio?: string}
@module("node:child_process")
external spawnWithEnv: (string, array<string>, envOptions) => spawned = "spawnSync"

type child
type stream
type piped = {cwd: string, stdio: array<string>, env?: Dict.t<string>}
@module("node:child_process") external spawn: (string, array<string>, piped) => child = "spawn"
@get external childOut: child => stream = "stdout"
@get external childErr: child => stream = "stderr"
@send external onChunk: (stream, @as("data") _, bytes => unit) => unit = "on"
@send external onClose: (child, @as("close") _, Nullable.t<int> => unit) => unit = "on"
@send external chunkText: (bytes, @as("utf8") _) => string = "toString"
@val @scope(("process", "stdout")) external write: string => unit = "write"

/** A command's output shown as it arrives and kept, and its status: a long run is never silent. */
let stream = (~cwd, command, commandArgs) =>
  Promise.make((resolve, _) => {
    let child = spawn(command, commandArgs, {cwd, stdio: ["ignore", "pipe", "pipe"]})
    let seen = []
    let take = chunk => {
      let text = chunk->chunkText
      write(text)
      seen->Array.push(text)
    }
    child->childOut->onChunk(take)
    child->childErr->onChunk(take)
    child->onClose(code => resolve((code->Nullable.getOr(1), seen->Array.join(""))))
  })
