open Testing

let scratch = []
afterEach(() => {
  scratch->Array.forEach(dir => Node.rmSync(dir, {recursive: true, force: true}))
  scratch->Array.splice(~start=0, ~remove=scratch->Array.length, ~insert=[])
})

let directory = (files: array<(string, string)>) => {
  let dir = Node.mkdtempSync(Node.join([Node.tmpdir(), "artifact-test-"]))
  scratch->Array.push(dir)
  tree(dir, files)
  dir
}

let bucket: Artifact.bucket = {
  endpoint: Net.url("http://localhost:9000"),
  region: "us-east-1",
  bucket: "builds",
  keyId: "id",
  secret: "secret",
  virtualHost: false,
}

describe("signing", () => {
  test("gives the signature of AWS's own example of a signed GET", () => {
    // "Example: GET Object" in Amazon S3's "Signature Calculations for the Authorization Header".
    let signed = Artifact.authorization(
      {
        method: "GET",
        path: "/test.txt",
        query: Dict.make(),
        headers: Dict.fromArray([
          ("host", "examplebucket.s3.amazonaws.com"),
          ("range", "bytes=0-9"),
          (
            "x-amz-content-sha256",
            "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
          ),
          ("x-amz-date", "20130524T000000Z"),
        ]),
      },
      "us-east-1",
      "AKIAIOSFODNN7EXAMPLE",
      "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY",
    )
    expect(signed)->toBe(
      "AWS4-HMAC-SHA256 Credential=AKIAIOSFODNN7EXAMPLE/20130524/us-east-1/s3/aws4_request, " ++
      "SignedHeaders=host;range;x-amz-content-sha256;x-amz-date, " ++ "Signature=f0e8bdb87c964420e857bd35b5d6ed310bd44f0170aba48dd91039c6036bdb41",
    )
  })

  test("addresses a key path-style unless the bucket is its own host", () => {
    expect(Artifact.address(bucket, "o/r/1/declarations.zip"))->toEqual({
      Artifact.host: "localhost:9000",
      name: "localhost",
      path: "/builds/o/r/1/declarations.zip",
    })
    expect(Artifact.address({...bucket, virtualHost: true}, ""))->toEqual({
      Artifact.host: "builds.localhost:9000",
      name: "builds.localhost",
      path: "/",
    })
  })
})

describe("configuration", () => {
  let env = [
    ("ARTIFACTS_ENDPOINT", "https://s3.example.com"),
    ("ARTIFACTS_REGION", "auto"),
    ("ARTIFACTS_BUCKET", "builds"),
    ("ARTIFACTS_WRITE_KEY_ID", "id"),
    ("ARTIFACTS_WRITE_SECRET", "secret"),
  ]
  let with_ = more => Dict.fromArray(Array.concat(env, more))

  test("is read by name, path-style unless asked", () => {
    expect(Artifact.configured(with_([])).virtualHost)->toBe(false)
    expect(Artifact.configured(with_([("ARTIFACTS_VIRTUAL_HOST", "true")])).virtualHost)->toBe(true)
  })

  test("names everything missing, and refuses an endpoint with a path", () => {
    expect(() => Artifact.configured(Dict.fromArray([("ARTIFACTS_REGION", "auto")])))->toThrow(
      "ARTIFACTS_ENDPOINT, ARTIFACTS_BUCKET, ARTIFACTS_WRITE_KEY_ID, ARTIFACTS_WRITE_SECRET not set",
    )
    expect(
      () => Artifact.configured(with_([("ARTIFACTS_ENDPOINT", "https://s3.example.com/x")])),
    )->toThrow("no path")
  })
})

describe("pruning", () => {
  let prefix = "monoflake/platform/"
  let both = (run, name) => [
    `${prefix}${Int.toString(run)}/${name}.zip`,
    `${prefix}${Int.toString(run)}/${name}.json`,
  ]
  let many = (runs, name) => runs->Array.flatMap(run => both(run, name))

  test("keeps the newest two runs of the artifact, by number, digest before zip", () => {
    let keys = Array.concat(
      many([9, 10, 100], "deploy-geo-arm64"),
      many([9, 10, 100], "deploy-geo-amd64"),
    )
    expect(Artifact.pruned(keys, prefix, "deploy-geo-arm64"))->toEqual([
      `${prefix}9/deploy-geo-arm64.json`,
      `${prefix}9/deploy-geo-arm64.zip`,
    ])
  })

  test("takes the declarations of a run left with nothing else", () => {
    let keys =
      [
        both(1, "declarations"),
        both(1, "deploy-geo-arm64"),
        both(2, "declarations"),
        both(2, "deploy-geo-arm64"),
        both(2, "deploy-shot-arm64"),
        both(3, "declarations"),
        both(3, "deploy-geo-arm64"),
        both(4, "declarations"),
        both(4, "deploy-geo-arm64"),
      ]->Array.flat
    expect(Artifact.pruned(keys, prefix, "deploy-geo-arm64"))->toEqual(
      [
        both(2, "deploy-geo-arm64")->Array.toReversed,
        both(1, "deploy-geo-arm64")->Array.toReversed,
        both(1, "declarations")->Array.toReversed,
      ]->Array.flat,
    )
  })

  test("keeps a run that changed declarations alone until two newer runs exist", () => {
    let keys =
      [
        both(7, "declarations"),
        both(8, "declarations"),
        both(8, "deploy-host-arm64"),
        both(9, "declarations"),
      ]->Array.flat
    expect(Artifact.pruned(keys, prefix, "deploy-host-arm64"))->toEqual(
      both(7, "declarations")->Array.toReversed,
    )
    // Run 9 is among the newest two until a second run after it.
    keys->Array.pushMany(Array.concat(both(10, "declarations"), both(10, "deploy-host-arm64")))
    expect(Artifact.pruned(keys, prefix, "deploy-host-arm64"))->toEqual(
      both(7, "declarations")->Array.toReversed,
    )
    keys->Array.pushMany(both(11, "deploy-host-arm64"))
    expect(Artifact.pruned(keys, prefix, "deploy-host-arm64"))->toEqual(
      [
        both(8, "deploy-host-arm64")->Array.toReversed,
        both(7, "declarations")->Array.toReversed,
        both(8, "declarations")->Array.toReversed,
        both(9, "declarations")->Array.toReversed,
      ]->Array.flat,
    )
  })

  test("leaves what is not a run of this repository alone", () => {
    let keys = Array.concat(
      many([1, 2, 3], "worker-hook"),
      [
        "monoflake/platform/notes.txt",
        "monoflake/platform/x/worker-hook.zip",
        "monoflake/infra/1/worker-hook.zip",
      ],
    )
    expect(Artifact.pruned(keys, prefix, "worker-hook"))->toEqual(
      both(1, "worker-hook")->Array.toReversed,
    )
  })
})

let unzip = args => Node.execFileSync("unzip", args, {encoding: "utf8"})
let deflatedText = /deflated/
let storedText = /none \(stored\)/
let methodStored = /compression method:\s+none \(stored\)/

describe("zipping", () => {
  test("holds the files at its root, hidden ones only when asked", () => {
    let dir = directory([("a.toml", "a"), ("assets/.assetsignore", "x"), ("assets/b/c.js", "c")])
    expect(Artifact.files(dir, false)->Array.map(entry => entry.name))->toEqual([
      "a.toml",
      "assets/b/c.js",
    ])
    expect(Artifact.files(dir, true)->Array.map(entry => entry.name))->toEqual([
      "a.toml",
      "assets/.assetsignore",
      "assets/b/c.js",
    ])
  })

  test("deflates, or stores, and unzip reads back every byte", () => {
    let content = String.repeat("service = \"geo\"\n", 1000)
    let dir = directory([("image.tar", content), ("service.toml", "name = \"geo\"\n")])
    [false, true]->Array.forEach(
      stored => {
        let out = Node.join([dir, "..", `${stored ? "true" : "false"}.zip`])
        scratch->Array.push(out)
        Artifact.zip(Artifact.files(dir, false), out, stored)
        expect(unzip(["-tq", out]))->toContain("No errors detected")
        expect(unzip(["-p", out, "image.tar"]))->toBe(content)
        let listed = unzip(["-Zv", out])
        expect(listed)->toMatch(stored ? methodStored : deflatedText)
        expect(listed)->negated->toMatch(stored ? deflatedText : storedText)
        expect(Artifact.digest(out).size)->toBeGreaterThan(0.)
        Node.rmSync(out, {recursive: true, force: true})
      },
    )
  })
})

type asked = {method: string, path: string, query: Dict.t<string>}

/** A fake S3 on a free port, answering each request with `answer` and recording every one. */
let store = async (answer: asked => (int, string)) => {
  let asked = []
  let server = createServer((request, response) => {
    let url = Net.url(`http://localhost${request->requestUrl}`)
    let one = {
      method: request->requestMethod,
      path: url->Net.pathname,
      query: Net.fromEntries(url->Net.searchParams),
    }
    asked->Array.push(one)
    let (status, body) = answer(one)
    response
    ->writeHead(status, Dict.fromArray([("content-type", "application/xml")]))
    ->endResponse(body)
  })
  await Promise.make((resolve, _) => server->listen(0, () => resolve()))
  let port = (server->serverAddress).port
  (
    {...bucket, endpoint: Net.url(`http://localhost:${Int.toString(port)}`)},
    asked,
    () => Promise.make((resolve, _) => server->close(() => resolve())),
  )
}

/** A ListObjectVersions page holding `entries`, as `(element, key, versionId)`. */
let page = (entries: array<(string, string, string)>, ~next=?) => {
  let listed =
    entries
    ->Array.map(((element, key, id)) =>
      `<${element}><Key>${key}</Key><VersionId>${id}</VersionId></${element}>`
    )
    ->Array.join("")
  let more = switch next {
  | Some((key, id)) =>
    `<IsTruncated>true</IsTruncated><NextKeyMarker>${key}</NextKeyMarker><NextVersionIdMarker>${id}</NextVersionIdMarker>`
  | None => "<IsTruncated>false</IsTruncated>"
  }
  `<?xml version="1.0" encoding="UTF-8"?><ListVersionsResult>${more}${listed}</ListVersionsResult>`
}

/** What `asked` deleted, as `key` or `key@version`. */
let deleted = (asked: array<asked>) =>
  asked
  ->Array.filter(one => one.method == "DELETE")
  ->Array.map(one => {
    let key = one.path->String.replace("/builds/", "")
    switch one.query->Dict.get("versionId") {
    | Some(version) => `${key}@${version}`
    | None => key
    }
  })

describe("erasing", () => {
  let closing = []
  afterEachAsync(async () => {
    let _ = await Promise.all(closing->Array.map(close => close()))
    closing->Array.splice(~start=0, ~remove=closing->Array.length, ~insert=[])
  })
  let key = "o/r/1/deploy-a.zip"

  testAsync("deletes the key, then finds no version left of it", async () => {
    let (fake, asked, close) = await store(one => (one.method == "DELETE" ? 204 : 200, page([])))
    closing->Array.push(close)
    await Artifact.erase(fake, key)
    expect(asked)->toEqual([
      {method: "DELETE", path: "/builds/o/r/1/deploy-a.zip", query: Dict.make()},
      {method: "GET", path: "/builds", query: Dict.fromArray([("versions", ""), ("prefix", key)])},
    ])
  })

  testAsync("deletes every version and the marker the DELETE left", async () => {
    let (fake, asked, close) = await store(
      one =>
        one.method == "DELETE"
          ? (204, "")
          : (
              200,
              page([("DeleteMarker", key, "hide"), ("Version", key, "v2"), ("Version", key, "v1")]),
            ),
    )
    closing->Array.push(close)
    await Artifact.erase(fake, key)
    expect(deleted(asked))->toEqual([key, `${key}@hide`, `${key}@v2`, `${key}@v1`])
  })

  testAsync("follows a truncated listing by its key and version markers", async () => {
    let (fake, asked, close) = await store(
      one =>
        if one.method == "DELETE" {
          (204, "")
        } else if one.query->Dict.get("key-marker") == None {
          (200, page([("DeleteMarker", key, "hide"), ("Version", key, "v3")], ~next=(key, "v3")))
        } else {
          (200, page([("Version", key, "v2"), ("Version", key, "v1")]))
        },
    )
    closing->Array.push(close)
    expect(await Artifact.versions(fake, key))->toEqual(["hide", "v3", "v2", "v1"])
    expect(asked[1]->Option.map(one => one.query))->toEqual(
      Some(
        Dict.fromArray([
          ("versions", ""),
          ("prefix", key),
          ("key-marker", key),
          ("version-id-marker", "v3"),
        ]),
      ),
    )
  })

  testAsync("takes a store that does not list versions as keeping none", async () => {
    let (fake, asked, close) = await store(
      one =>
        one.method == "DELETE" ? (204, "") : (501, "<Error><Code>NotImplemented</Code></Error>"),
    )
    closing->Array.push(close)
    await Artifact.erase(fake, key)
    // Answered once, never tried again as a 5xx would be.
    expect(asked->Array.map(one => one.method))->toEqual(["DELETE", "GET"])
  })

  testAsync(
    "takes a store answering the versions listing with its objects as keeping none",
    async () => {
      // A store that passes over `versions` lists the key itself, a version of nothing.
      let (fake, _, close) = await store(
        one =>
          one.method == "DELETE"
            ? (204, "")
            : (
                200,
                `<ListBucketResult><Contents><Key>${key}</Key></Contents><IsTruncated>false</IsTruncated></ListBucketResult>`,
              ),
      )
      closing->Array.push(close)
      expect(await Artifact.versions(fake, key))->toEqual([])
    },
  )

  testAsync("never touches a sibling the key is a prefix of", async () => {
    let (fake, asked, close) = await store(
      one =>
        one.method == "DELETE"
          ? (204, "")
          : (
              200,
              page([
                ("Version", "a/b", "mine"),
                ("DeleteMarker", "a/bc", "theirs"),
                ("Version", "a/bc", "theirs-too"),
              ]),
            ),
    )
    closing->Array.push(close)
    await Artifact.erase(fake, "a/b")
    expect(deleted(asked))->toEqual(["a/b", "a/b@mine"])
  })

  testAsync("refuses a listing that fails for any other reason", async () => {
    let (fake, _, close) = await store(
      one => one.method == "DELETE" ? (204, "") : (403, "<Error><Code>AccessDenied</Code></Error>"),
    )
    closing->Array.push(close)
    await expect(Artifact.erase(fake, "a/b"))->rejects->toThrowAsync("403 AccessDenied")
  })
})
