open Testing

let old = "sha256:" ++ String.repeat("1", 64)
let now = "sha256:" ++ String.repeat("2", 64)
let other = "sha256:" ++ String.repeat("3", 64)

let dockerfile = `ARG VERSION=1

FROM --platform=$BUILDPLATFORM busybox:1.37.0-glibc@${old} AS fetch-amd64
FROM --platform=$BUILDPLATFORM busybox:1.37.0-glibc@${old} AS fetch-arm64
FROM fetch-\${TARGETARCH} AS fetch
FROM gcr.io/distroless/cc-debian13:nonroot@${other}
FROM alpine:3.22`

describe("a base", () => {
  test("is a FROM pinned by digest, read by its line, a stage or a bare tag passed over", () => {
    expect(
      Images.bases(dockerfile)->Array.map(
        ({index, image, tag, digest}) => (index, image, tag, digest),
      ),
    )->toEqual([
      (2, "busybox", "1.37.0-glibc", old),
      (3, "busybox", "1.37.0-glibc", old),
      (5, "gcr.io/distroless/cc-debian13", "nonroot", other),
    ])
  })

  test("moves to its tag's digest, its platform, stage name and tag kept", () => {
    let moved = Images.rebased(dockerfile, dict{"busybox:1.37.0-glibc": now})->String.split("\n")
    expect(moved->Array.get(2))->toEqual(
      Some(`FROM --platform=$BUILDPLATFORM busybox:1.37.0-glibc@${now} AS fetch-amd64`),
    )
    expect(moved->Array.get(5))->toEqual(dockerfile->String.split("\n")->Array.get(5))
    expect(moved->Array.get(6))->toEqual(Some("FROM alpine:3.22"))
    expect(Images.rebased(dockerfile, dict{}))->toBe(dockerfile)
  })
})

describe("a registry", () => {
  test("serves an image from Docker Hub unless its first part names a host", () => {
    expect(Images.located("busybox"))->toEqual(("registry-1.docker.io", "library/busybox"))
    expect(Images.located("canmi/workerd"))->toEqual(("registry-1.docker.io", "canmi/workerd"))
    expect(Images.located("docker.io/canmi/workerd"))->toEqual((
      "registry-1.docker.io",
      "canmi/workerd",
    ))
    expect(Images.located("gcr.io/distroless/cc-debian13"))->toEqual((
      "gcr.io",
      "distroless/cc-debian13",
    ))
    expect(Images.located("localhost:5055/canmi/x"))->toEqual(("localhost:5055", "canmi/x"))
  })

  test("challenges with where its token is asked for, its service and scope", () => {
    expect(
      Images.challenged(`Bearer realm="https://auth.docker.io/token",service="registry.docker.io",scope="repository:library/busybox:pull"`),
    )->toEqual(
      Some(
        "https://auth.docker.io/token?service=registry.docker.io&scope=repository%3Alibrary%2Fbusybox%3Apull",
      ),
    )
    expect(Images.challenged(`Bearer realm="https://gcr.io/v2/token"`))->toEqual(
      Some("https://gcr.io/v2/token"),
    )
    expect(Images.challenged(`Basic realm="x"`))->toEqual(None)
  })
})

describe("the Dockerfiles", () => {
  let root = temporaryRoot("images")
  test("are every file named Dockerfile, what a tool wrote or a checkout holds passed over", () => {
    tree(
      root.contents,
      [
        ("images/workerd/Dockerfile", ""),
        ("images/wasmtime/Dockerfile", ""),
        ("images/wasmtime/Dockerfile.old", ""),
        ("node_modules/x/Dockerfile", ""),
        ("dist/Dockerfile", ""),
        ("Dockerfile", ""),
      ],
    )
    expect(
      Images.dockerfiles(root.contents)->Array.map(path => Node.relative(root.contents, path)),
    )->toEqual(["Dockerfile", "images/wasmtime/Dockerfile", "images/workerd/Dockerfile"])
  })
})
