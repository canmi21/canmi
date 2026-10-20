/**
 * One Deploy run's artifact into the bucket, RFC q28g5: `node artifact.res.mjs <name> <dir> [--store]
 * [--hidden] [--dry-run]`, from the workspace's checkout in a repository's CI. Zipped as
 * actions/upload-artifact zipped it, put at `<owner>/<repo>/<run>/<name>.zip`, then `<name>.json`
 * beside it; a `deploy-*` or `worker-*` then prunes the repository's runs. Reached by the S3 API
 * alone, signed here, from ARTIFACTS_ENDPOINT, _REGION, _BUCKET, _WRITE_KEY_ID and _WRITE_SECRET,
 * path-style unless ARTIFACTS_VIRTUAL_HOST is `true`.
 */
let usage = "usage: artifact.res.mjs <name> <dir> [--store] [--hidden] [--dry-run]"
/** The names a Deploy run's artifacts take. */
let artifactName = /^(declarations|deploy-[a-z0-9-]+|worker-[a-z0-9-]+)$/
/** The runs kept of each pruned artifact, and the repository's runs no sweep touches. */
let kept = 2
/** upload-artifact's default compression level. */
let level = 6
let chunk = 1048576
let attempts = 3
/** The largest a zip without ZIP64 can say, and the largest one PUT may carry. */
let zipLimit = 4294967295.

type bucket = {
  endpoint: Net.url,
  region: string,
  bucket: string,
  keyId: string,
  secret: string,
  virtualHost: bool,
}

/** A file in the zip: its path there, `/`-separated, and where it is on disk. */
type entry = {name: string, path: string}

/** The files under `dir`, sorted, with what a leading dot hides left out unless `hidden`. */
let rec files = (dir: string, hidden: bool, ~prefix=""): array<entry> =>
  Node.readdir(dir)
  ->Array.toSorted(String.compare)
  ->Array.flatMap(name =>
    if !hidden && name->String.startsWith(".") {
      []
    } else {
      let path = Node.join([dir, name])
      // Followed, as upload-artifact follows a link to what it points at.
      let stats = Net.statSync(path)
      if stats->Net.isDirectory {
        files(path, hidden, ~prefix=`${prefix}${name}/`)
      } else if stats->Net.isFile {
        [{name: `${prefix}${name}`, path}]
      } else {
        []
      }
    }
  )

/** A date as a zip's DOS time and date, in local time as archiver writes it. */
let dos = (date: Date.t) => {
  let time = Int.bitwiseOr(
    Int.bitwiseOr(Int.shiftLeft(date->Date.getHours, 11), Int.shiftLeft(date->Date.getMinutes, 5)),
    Int.shiftRight(date->Date.getSeconds, 1),
  )
  let day = Int.bitwiseOr(
    Int.bitwiseOr(
      Int.shiftLeft(Math.Int.max(date->Date.getFullYear - 1980, 0), 9),
      Int.shiftLeft(date->Date.getMonth + 1, 5),
    ),
    date->Date.getDate,
  )
  (time, day)
}

/** Calls `each` with every chunk of the file at `path`. */
let chunks = (path: string, each: Net.bytes => unit) => {
  let fd = Net.openSync(path, "r")
  let buffer = Net.alloc(chunk)
  try {
    let read = ref(Net.readSync(fd, buffer))
    while read.contents > 0 {
      each(buffer->Net.subarray(0, read.contents))
      read := Net.readSync(fd, buffer)
    }
    Net.closeSync(fd)
  } catch {
  | error =>
    Net.closeSync(fd)
    throw(error)
  }
}

/** A number as JavaScript's `>>> 0` reads it, unsigned. */
let unsigned: float => float = %raw(`value => value >>> 0`)
let unsignedInt: int => float = %raw(`value => value >>> 0`)

/**
 * Writes `entries` to a zip at `out`, each deflated or, with `store`, stored, so a large image is
 * streamed rather than held. No ZIP64: an entry or a zip past 4 GiB is refused.
 */
let zip = (entries: array<entry>, out: string, store: bool) => {
  let fd = Net.openSync(out, "w")
  let central = []
  let offset = ref(0.)
  let write = buffer => {
    Net.writeSync(fd, buffer)->ignore
    offset := offset.contents +. Int.toFloat(buffer->Net.size)
  }
  let finish = () => Net.closeSync(fd)
  try {
    entries->Array.forEach(entry => {
      let stats = Net.statSync(entry.path)
      if stats.size > zipLimit {
        JsError.throwWithMessage(`${entry.name} is past what a zip holds`)
      }
      let name = Net.fromText(entry.name)
      // Bit 11, the name is UTF-8, set only where it is not ASCII, as archiver sets it.
      let flags = name->Net.size == entry.name->String.length ? 0 : 0x0800
      let (time, day) = dos(stats.mtime)
      let crc = ref(0.)
      let deflated = if store {
        chunks(entry.path, part => crc := Net.crc32(part, crc.contents))
        None
      } else {
        let whole = Net.alloc(stats.size->Float.toInt)
        let at = ref(0)
        chunks(entry.path, part => {
          part->Net.copy(whole, at.contents)->ignore
          at := at.contents + part->Net.size
        })
        crc := Net.crc32(whole, 0.)
        Some(Net.deflateRawSync(whole, {level: level}))
      }
      let method_ = store ? 0 : 8
      let size = switch deflated {
      | Some(deflated) => Int.toFloat(deflated->Net.size)
      | None => stats.size
      }
      let at = offset.contents
      let local = Net.alloc(30)
      local->Net.writeUInt32(67324752., 0)->ignore
      local->Net.writeUInt16(20, 4)->ignore
      local->Net.writeUInt16(flags, 6)->ignore
      local->Net.writeUInt16(method_, 8)->ignore
      local->Net.writeUInt16(time, 10)->ignore
      local->Net.writeUInt16(day, 12)->ignore
      local->Net.writeUInt32(unsigned(crc.contents), 14)->ignore
      local->Net.writeUInt32(size, 18)->ignore
      local->Net.writeUInt32(stats.size, 22)->ignore
      local->Net.writeUInt16(name->Net.size, 26)->ignore
      local->Net.writeUInt16(0, 28)->ignore
      write(local)
      write(name)
      switch deflated {
      | Some(deflated) => write(deflated)
      | None => chunks(entry.path, write)
      }
      if offset.contents > zipLimit {
        JsError.throwWithMessage(`the zip is past 4 GiB at ${entry.name}`)
      }
      let header = Net.alloc(46)
      header->Net.writeUInt32(33639248., 0)->ignore
      // Made by Unix at 4.5, so the mode below is read, as GitHub's own zips say.
      header->Net.writeUInt16(Int.bitwiseOr(Int.shiftLeft(3, 8), 45), 4)->ignore
      header->Net.writeUInt16(20, 6)->ignore
      header->Net.writeUInt16(flags, 8)->ignore
      header->Net.writeUInt16(method_, 10)->ignore
      header->Net.writeUInt16(time, 12)->ignore
      header->Net.writeUInt16(day, 14)->ignore
      header->Net.writeUInt32(unsigned(crc.contents), 16)->ignore
      header->Net.writeUInt32(size, 20)->ignore
      header->Net.writeUInt32(stats.size, 24)->ignore
      header->Net.writeUInt16(name->Net.size, 28)->ignore
      // The mode above MS-DOS's archive bit.
      header
      ->Net.writeUInt32(
        unsignedInt(Int.bitwiseOr(Int.shiftLeft(Int.bitwiseAnd(stats.mode, 0xffff), 16), 0x20)),
        38,
      )
      ->ignore
      header->Net.writeUInt32(at, 42)->ignore
      central->Array.pushMany([header, name])
    })
    let start = offset.contents
    central->Array.forEach(write)
    let end = Net.alloc(22)
    end->Net.writeUInt32(101010256., 0)->ignore
    end->Net.writeUInt16(entries->Array.length, 8)->ignore
    end->Net.writeUInt16(entries->Array.length, 10)->ignore
    end->Net.writeUInt32(offset.contents -. start, 12)->ignore
    end->Net.writeUInt32(start, 16)->ignore
    write(end)
    finish()
  } catch {
  | error =>
    finish()
    throw(error)
  }
}

type digest = {sha256: string, size: float}

/** The file's sha256, in hex, and its size. */
let digest = (path: string): digest => {
  let hash = Net.createHash("sha256")
  let size = ref(0.)
  chunks(path, part => {
    hash->Net.updateBytes(part)->ignore
    size := size.contents +. Int.toFloat(part->Net.size)
  })
  {sha256: hash->Net.hexDigest, size: size.contents}
}

let sha256Text = text => Net.createHash("sha256")->Net.updateText(text)->Net.hexDigest
let sha256Bytes = bytes => Net.createHash("sha256")->Net.updateBytes(bytes)->Net.hexDigest

let reserved = /[!'()*]/g

/** RFC 3986's unreserved characters left alone, as SigV4 encodes. */
let encode = (text: string) =>
  text
  ->encodeURIComponent
  ->String.replaceRegExpBy0Unsafe(reserved, (~match, ~offset as _, ~input as _) =>
    `%${match->String.charCodeAt(0)->Option.getOr(0)->Int.toString(~radix=16)->String.toUpperCase}`
  )

type signable = {
  method: string,
  /** The path, already encoded, and the query, as sent. */
  path: string,
  query: Dict.t<string>,
  /** Every header signed, `host`, `x-amz-date` and `x-amz-content-sha256` among them. */
  headers: Dict.t<string>,
}

let byFirst = ((a, _), (b, _)) => a < b ? -1. : 1.

/** The Authorization header SigV4 gives `signable` for S3 in `region`. */
let authorization = (signable: signable, region: string, keyId: string, secret: string): string => {
  let headers =
    signable.headers
    ->Dict.toArray
    ->Array.map(((name, value)) => (name->String.toLowerCase, value->String.trim))
    ->Array.toSorted(byFirst)
  let signed = headers->Array.map(((name, _)) => name)->Array.join(";")
  let query =
    signable.query
    ->Dict.toArray
    ->Array.map(((key, value)) => `${encode(key)}=${encode(value)}`)
    ->Array.toSorted(String.compare)
    ->Array.join("&")
  let canonical =
    [
      signable.method,
      signable.path,
      query,
      headers->Array.map(((name, value)) => `${name}:${value}\n`)->Array.join(""),
      signed,
      signable.headers->Dict.get("x-amz-content-sha256")->Option.getOr(""),
    ]->Array.join("\n")
  let stamp = signable.headers->Dict.get("x-amz-date")->Option.getOr("")
  let day = stamp->String.slice(~start=0, ~end=8)
  let scope = `${day}/${region}/s3/aws4_request`
  let toSign = ["AWS4-HMAC-SHA256", stamp, scope, sha256Text(canonical)]->Array.join("\n")
  let key = ["s3", "aws4_request"]->Array.reduce(
    Net.hmacBytes(Net.hmacText(`AWS4${secret}`)->Net.updateText(day)->Net.digestBytes)
    ->Net.updateText(region)
    ->Net.digestBytes,
    (key, part) => Net.hmacBytes(key)->Net.updateText(part)->Net.digestBytes,
  )
  let signature = Net.hmacBytes(key)->Net.updateText(toSign)->Net.hexDigest
  `AWS4-HMAC-SHA256 Credential=${keyId}/${scope}, SignedHeaders=${signed}, Signature=${signature}`
}

type address = {host: string, name: string, path: string}

/** Where `key` is in the bucket, path-style or by virtual host: the Host, the name to dial, the path. */
let address = (bucket: bucket, key: string): address => {
  let encoded = key != "" ? `/${key->String.split("/")->Array.map(encode)->Array.join("/")}` : ""
  let host = bucket.endpoint->Net.host
  let hostname = bucket.endpoint->Net.hostname
  bucket.virtualHost
    ? {
        host: `${bucket.bucket}.${host}`,
        name: `${bucket.bucket}.${hostname}`,
        path: encoded != "" ? encoded : "/",
      }
    : {host, name: hostname, path: `/${encode(bucket.bucket)}${encoded}`}
}

type answer = {status: int, body: string}

/** What a request carries: nothing, bytes, or a file streamed with its digest. */
type body = Nothing | Bytes(Net.bytes) | File(string, digest)

let stampDashes = /[-:]/g
let stampMillis = /\.\d{3}/

/** One signed request. */
let send = (
  bucket: bucket,
  method: string,
  key: string,
  query: Dict.t<string>,
  body: body,
  ~kind=?,
): promise<answer> => {
  let {host, name, path} = address(bucket, key)
  let payload = switch body {
  | Nothing => sha256Text("")
  | Bytes(bytes) => sha256Bytes(bytes)
  | File(_, digest) => digest.sha256
  }
  let stamp =
    Date.make()
    ->Date.toISOString
    ->String.replaceRegExp(stampDashes, "")
    ->String.replaceRegExp(stampMillis, "")
  let headers = Dict.fromArray([
    ("host", host),
    ("x-amz-content-sha256", payload),
    ("x-amz-date", stamp),
  ])
  let signature = authorization(
    {method, path, query, headers},
    bucket.region,
    bucket.keyId,
    bucket.secret,
  )
  let length = switch body {
  | Nothing => "0"
  | Bytes(bytes) => Int.toString(bytes->Net.size)
  | File(_, digest) => Float.toString(digest.size)
  }
  let search = Net.params(query)->Net.paramsText
  let secure = bucket.endpoint->Net.protocol == "https:"
  let sent = headers->Dict.copy
  sent->Dict.set("authorization", signature)
  sent->Dict.set("content-length", length)
  switch kind {
  | Some(kind) => sent->Dict.set("content-type", kind)
  | None => ()
  }
  let port = bucket.endpoint->Net.port
  Promise.make((resolve, reject) => {
    let options: Net.requestOptions = {
      method,
      host: name,
      port: port != "" ? port : secure ? "443" : "80",
      path: search != "" ? `${path}?${search}` : path,
      headers: sent,
      timeout: 120000,
    }
    let respond = response => {
      let parts = []
      response->Net.onData(part => parts->Array.push(part))
      response->Net.onEnd(() =>
        resolve({
          status: response->Net.statusCode->Nullable.getOr(0),
          body: Net.concat(parts)->Net.text,
        })
      )
      response->Net.onIncomingError(error => reject(JsExn.anyToExnInternal(error)))
    }
    let request = secure ? Net.httpsRequest(options, respond) : Net.httpRequest(options, respond)
    request->Net.onTimeout(() => request->Net.destroy(Net.error("no answer within 120 seconds")))
    request->Net.onRequestError(error => reject(JsExn.anyToExnInternal(error)))
    switch body {
    | Nothing => request->Net.endEmpty
    | Bytes(bytes) => request->Net.endWith(bytes)
    | File(path, _) =>
      Net.createReadStream(path)
      ->Net.onStreamError(error => reject(JsExn.anyToExnInternal(error)))
      ->Net.pipe(request)
    }
  })
}

let codeOf = /<Code>([^<]*)<\/Code>/
let messageOf = /<Message>([^<]*)<\/Message>/

let first = (pattern: RegExp.t, text: string) =>
  pattern
  ->RegExp.exec(text)
  ->Option.flatMap(result => result->RegExp.Result.matches->Array.get(0))
  ->Option.flatMap(x => x)

/** What S3 said went wrong, by its own code and message. */
let refusal = (answer: answer) =>
  `${Int.toString(answer.status)}${first(codeOf, answer.body)->Option.mapOr("", code =>
      ` ${code}`
    )}${first(messageOf, answer.body)->Option.mapOr("", message => `: ${message}`)}`

let wait = ms => Promise.make((resolve, _) => setTimeout(() => resolve(), ms)->ignore)

/**
 * `send`, tried again on a network error, a 5xx or a 429; anything else not 2xx throws, unless
 * its status is one of `tolerated`, which is answered as it came.
 */
let attempt = async (tolerated: array<int>, bucket, method, key, query, body, ~kind=?) => {
  let rec go = async tried => {
    let (answer, why) = switch await send(bucket, method, key, query, body, ~kind?) {
    | answer => (Some(answer), "")
    | exception JsExn(error) => (None, error->JsExn.message->Option.getOr(""))
    }
    switch answer {
    | Some(answer) if answer.status >= 200 && answer.status < 300 => answer
    | Some(answer) if tolerated->Array.includes(answer.status) => answer
    | _ =>
      let why = switch answer {
      | Some(answer) =>
        let why = refusal(answer)
        if answer.status < 500 && answer.status != 429 {
          JsError.throwWithMessage(`${method} ${key}: ${why}`)
        }
        why
      | None => why
      }
      if tried >= attempts {
        JsError.throwWithMessage(`${method} ${key}: ${why}, ${Int.toString(attempts)} times`)
      }
      Console.error(`artifact: ${method} ${key}: ${why}; trying again`)
      await wait(2000 * tried)
      await go(tried + 1)
    }
  }
  await go(1)
}

/** `send`, tried again on a network error, a 5xx or a 429; anything else not 2xx throws. */
let call = (bucket, method, key, query, body, ~kind=?) =>
  attempt([], bucket, method, key, query, body, ~kind?)

let unescape = text =>
  text
  ->String.replaceAll("&lt;", "<")
  ->String.replaceAll("&gt;", ">")
  ->String.replaceAll("&quot;", "\"")
  ->String.replaceAll("&apos;", "'")
  ->String.replaceAll("&amp;", "&")

let keyOf = /<Key>([^<]*)<\/Key>/g
let truncatedOf = /<IsTruncated>true<\/IsTruncated>/
let tokenOf = /<NextContinuationToken>([^<]*)<\/NextContinuationToken>/

/** Every key under `prefix`, across as many pages as ListObjectsV2 gives. */
let list = async (bucket: bucket, prefix: string): array<string> => {
  let keys = []
  let rec page = async token => {
    let query = Dict.fromArray([("list-type", "2"), ("prefix", prefix)])
    switch token {
    | Some(token) => query->Dict.set("continuation-token", token)
    | None => ()
    }
    let {body} = await call(bucket, "GET", "", query, Nothing)
    Graph.groups(keyOf, body)->Array.forEach(key => keys->Array.push(unescape(key)))
    if truncatedOf->RegExp.test(body) {
      switch first(tokenOf, body)->Option.map(unescape) {
      | Some(token) if token != "" => await page(Some(token))
      | _ => JsError.throwWithMessage(`listing ${prefix}: truncated with no token`)
      }
    }
  }
  await page(None)
  keys
}

/** The answers a store gives a request it does not implement, by status or by S3's code. */
let unimplemented = [400, 405, 501]
let unimplementedCodes = ["NotImplemented", "MethodNotAllowed"]

let entryOf = /<(Version|DeleteMarker)>([\s\S]*?)<\/\1>/g
let singleKey = /<Key>([^<]*)<\/Key>/
let versionOf = /<VersionId>([^<]*)<\/VersionId>/
let nextKeyOf = /<NextKeyMarker>([^<]*)<\/NextKeyMarker>/
let nextVersionOf = /<NextVersionIdMarker>([^<]*)<\/NextVersionIdMarker>/

/** Every second group of global `pattern` in `text`, in order. */
let seconds = (pattern: RegExp.t, text: string) => {
  let found = []
  pattern->RegExp.setLastIndex(0)
  let rec next = () =>
    switch pattern->RegExp.exec(text) {
    | Some(result) =>
      switch result->RegExp.Result.matches->Array.get(1) {
      | Some(Some(inner)) => found->Array.push(inner)
      | _ => ()
      }
      next()
    | None => ()
    }
  next()
  found
}

/**
 * The id of every version and delete marker of exactly `key`, across as many pages as
 * ListObjectVersions gives -- a sibling it shares a prefix with is passed over. None where the
 * store does not implement the listing, as a store that keeps no versions need not.
 */
let versions = async (bucket: bucket, key: string): array<string> => {
  let ids = []
  let rec page = async marker => {
    let query = Dict.fromArray([("versions", ""), ("prefix", key)])
    switch marker {
    | Some((next, version)) =>
      query->Dict.set("key-marker", next)
      query->Dict.set("version-id-marker", version)
    | None => ()
    }
    let answer = await attempt(unimplemented, bucket, "GET", "", query, Nothing)
    if answer.status >= 300 {
      let code = first(codeOf, answer.body)->Option.getOr("")
      if !(answer.status == 501 || unimplementedCodes->Array.includes(code)) {
        JsError.throwWithMessage(`listing the versions of ${key}: ${refusal(answer)}`)
      }
      false
    } else {
      let body = answer.body
      seconds(entryOf, body)->Array.forEach(entry => {
        let held = first(singleKey, entry)->Option.mapOr("", unescape)
        switch first(versionOf, entry) {
        | Some(id) if held == key && id != "" => ids->Array.push(unescape(id))
        | _ => ()
        }
      })
      if truncatedOf->RegExp.test(body) {
        switch first(nextKeyOf, body) {
        | None =>
          JsError.throwWithMessage(`listing the versions of ${key}: truncated with no marker`)
        | Some(next) =>
          await page(Some((unescape(next), first(nextVersionOf, body)->Option.mapOr("", unescape))))
        }
      } else {
        true
      }
    }
  }
  await page(None) ? ids : []
}

/**
 * Deletes `key` as a DELETE always has, then every version and delete marker of it the store still
 * keeps, so the bytes go now; a store may keep versions with S3 Versioning off. A version already
 * gone is not an error.
 */
let erase = async (bucket: bucket, key: string) => {
  let _ = await call(bucket, "DELETE", key, Dict.make(), Nothing)
  let rec each = async remaining =>
    switch remaining {
    | list{} => ()
    | list{version, ...rest} =>
      let _ = await attempt(
        [404],
        bucket,
        "DELETE",
        key,
        Dict.fromArray([("versionId", version)]),
        Nothing,
      )
      await each(rest)
    }
  await each(List.fromArray(await versions(bucket, key)))
}

/** An artifact's keys with its `.json` first, so a digest never outlives the zip it names. */
let ordered = found =>
  found->Array.toSorted((a, b) =>
    a->String.endsWith(".json") ? -1. : b->String.endsWith(".json") ? 1. : 0.
  )

/** Run ids, the newest first: by number, since `100` is newer than `99`. */
let descending = runs =>
  runs->Array.toSorted((a, b) =>
    b->Float.fromString->Option.getOr(0.) -. a->Float.fromString->Option.getOr(0.)
  )

let runKey = /^(\d+)\/([^\/]+)\.(zip|json)$/

/**
 * The keys pruning `artifact` deletes from `keys`, every one under `prefix`: its runs older than
 * the newest `kept` holding it, then each run older than the repository's newest `kept` left
 * holding only `declarations`, so a run that changed declarations alone outlives two newer runs.
 */
let pruned = (keys: array<string>, prefix: string, artifact: string): array<string> => {
  let runs: Map.t<string, Map.t<string, array<string>>> = Map.make()
  keys->Array.forEach(key =>
    if key->String.startsWith(prefix) {
      switch runKey->RegExp.exec(key->String.slice(~start=prefix->String.length)) {
      | Some(result) =>
        switch result->RegExp.Result.matches {
        | [Some(run), Some(name), _] =>
          let held = runs->Map.get(run)->Option.getOr(Map.make())
          held->Map.set(name, Array.concat(held->Map.get(name)->Option.getOr([]), [key]))
          runs->Map.set(run, held)
        | _ => ()
        }
      | None => ()
      }
    }
  )
  let all = runs->Graph.keysOf
  let recent = all->descending->Array.slice(~start=0, ~end=kept)
  let doomed = []
  let holding =
    all
    ->Array.filter(run => runs->Map.get(run)->Option.mapOr(false, held => held->Map.has(artifact)))
    ->descending
  holding
  ->Array.slice(~start=kept)
  ->Array.forEach(run =>
    switch runs->Map.get(run) {
    | Some(held) =>
      doomed->Array.pushMany(held->Map.get(artifact)->Option.getOr([])->ordered)
      held->Map.delete(artifact)->ignore
    | None => ()
    }
  )
  runs->Map.forEachWithKey((held, run) =>
    if !(recent->Array.includes(run)) && held->Map.size == 1 && held->Map.has("declarations") {
      doomed->Array.pushMany(held->Map.get("declarations")->Option.getOr([])->ordered)
    }
  )
  doomed
}

let fail = message => {
  Console.error(`artifact: ${message}`)
  Node.exit(1)
}

/** The bucket as the environment names it; every missing name refused at once. */
let configured = (env: Dict.t<string>): bucket => {
  let names = [
    "ARTIFACTS_ENDPOINT",
    "ARTIFACTS_REGION",
    "ARTIFACTS_BUCKET",
    "ARTIFACTS_WRITE_KEY_ID",
    "ARTIFACTS_WRITE_SECRET",
  ]
  let get = name => env->Dict.get(name)->Option.getOr("")
  let missing = names->Array.filter(name => get(name) == "")
  if missing->Array.length > 0 {
    JsError.throwWithMessage(`${missing->Array.join(", ")} not set`)
  }
  let endpoint = Net.url(get("ARTIFACTS_ENDPOINT"))
  if endpoint->Net.pathname != "/" || endpoint->Net.search != "" {
    JsError.throwWithMessage("ARTIFACTS_ENDPOINT is an origin, with no path")
  }
  {
    endpoint,
    region: get("ARTIFACTS_REGION"),
    bucket: get("ARTIFACTS_BUCKET"),
    keyId: get("ARTIFACTS_WRITE_KEY_ID"),
    secret: get("ARTIFACTS_WRITE_SECRET"),
    virtualHost: get("ARTIFACTS_VIRTUAL_HOST") == "true",
  }
}

let repositoryName = /^[^\/]+\/[^\/]+$/
let runId = /^\d+$/

let main = async () => {
  let args = Node.args()
  let positional = args->Array.filter(arg => !(arg->String.startsWith("--")))
  let flags = args->Array.filter(arg => arg->String.startsWith("--"))
  let known = ["--store", "--hidden", "--dry-run"]
  let (name, dir) = switch positional {
  | [name, dir] if flags->Array.every(flag => known->Array.includes(flag)) => (name, dir)
  | _ => fail(usage)
  }
  if !(artifactName->RegExp.test(name)) {
    fail(`${name} is not declarations, deploy-<app>-<arch> or worker-<app>`)
  }
  let repository = Node.env->Dict.get("GITHUB_REPOSITORY")->Option.getOr("")
  let run = Node.env->Dict.get("GITHUB_RUN_ID")->Option.getOr("")
  if !(repositoryName->RegExp.test(repository)) || !(runId->RegExp.test(run)) {
    fail("GITHUB_REPOSITORY and GITHUB_RUN_ID name the run, and are not set")
  }
  let dry = flags->Array.includes("--dry-run")
  let bucket = switch configured(Node.env) {
  | bucket => Some(bucket)
  | exception JsExn(error) =>
    if !dry {
      fail(error->JsExn.message->Option.getOr(""))
    }
    None
  }
  let entries = files(dir, flags->Array.includes("--hidden"))
  if entries->Array.length == 0 {
    fail(`${dir} has no files to upload`)
  }
  let out = Node.join([
    Node.env->Dict.get("RUNNER_TEMP")->Option.getOr(Node.tmpdir()),
    `${name}.zip`,
  ])
  zip(entries, out, flags->Array.includes("--store"))
  let summary = digest(out)
  let prefix = `${repository}/`
  let key = `${prefix}${run}/${name}`
  let record = `{"sha256":"${summary.sha256}","size":${Float.toString(summary.size)}}`
  let prunes = name->String.startsWith("deploy-") || name->String.startsWith("worker-")
  Console.log(
    `artifact: ${Int.toString(entries->Array.length)} file(s) from ${dir}, ${Float.toString(
        summary.size,
      )} bytes zipped, sha256 ${summary.sha256}`,
  )
  switch (dry, bucket) {
  | (false, Some(bucket)) =>
    let _ = await call(
      bucket,
      "PUT",
      `${key}.zip`,
      Dict.make(),
      File(out, summary),
      ~kind="application/zip",
    )
    Net.rmFile(out)
    let _ = await call(
      bucket,
      "PUT",
      `${key}.json`,
      Dict.make(),
      Bytes(Net.fromText(record)),
      ~kind="application/json",
    )
    Console.log(`artifact: put ${key}.zip and ${key}.json`)
    if prunes {
      let doomed = pruned(await list(bucket, prefix), prefix, name)
      let rec each = async remaining =>
        switch remaining {
        | list{} => ()
        | list{gone, ...rest} =>
          await erase(bucket, gone)
          Console.log(`artifact: deleted ${gone}`)
          await each(rest)
        }
      await each(List.fromArray(doomed))
      if doomed->Array.length == 0 {
        Console.log(`artifact: nothing under ${prefix} to prune`)
      }
    }
  | _ =>
    Console.log(`artifact: would put ${key}.zip, then ${key}.json: ${record}`)
    if prunes {
      Console.log(
        `artifact: would delete ${name} from runs under ${prefix} older than the newest ${Int.toString(
            kept,
          )}, then the declarations of any run left with nothing else`,
      )
    }
    Net.rmFile(out)
  }
}

if Node.isMain {
  main()
  ->Promise.catch(error => {
    let message = switch error {
    | JsExn(error) => error->JsExn.message->Option.getOr("")
    | _ => "failed"
    }
    fail(message)
  })
  ->ignore
}
