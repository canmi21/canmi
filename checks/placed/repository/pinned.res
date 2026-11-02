/**
 * A pnpm repository's release age and each Dockerfile's base images,
 * docs/toolchain/dependencies.md and docs/toolchain/ci.md.
 */
let age = /^minimumReleaseAge:\s*(\d+)/m

/** Whether a path lies under a vendored or machine-made directory, which no rule here reads. */
let vendored = path =>
  path->String.split("/")->Array.some(part => part == "vendor" || part == "node_modules")

/** What is wrong with a pnpm repository's pnpm-workspace.yaml, given its text if it has one. */
let releaseAge = (text: option<string>): option<string> =>
  switch text {
  | None => Some("pnpm-workspace.yaml is missing, so no minimumReleaseAge holds a version back")
  | Some(text) =>
    switch age->RegExp.exec(text)->Option.map(RegExp.Result.matches) {
    | Some([Some(found)]) if Int.fromString(found)->Option.getOr(0) >= Toolchain.releaseAge => None
    | _ =>
      Some(
        `pnpm-workspace.yaml does not set minimumReleaseAge to ${Int.toString(
            Toolchain.releaseAge,
          )} or more`,
      )
    }
  }

let from = /^\s*FROM\s+(?:--\S+\s+)*(\S+)(?:\s+AS\s+(\S+))?\s*$/i
let digest = /^\S+:[^\/@:]+@sha256:[0-9a-f]{64}$/

/** Each FROM of a Dockerfile that names a base image by no tag and digest, `file` naming it. */
let images = (text, ~file): array<string> => {
  let stages = []
  text
  ->String.split("\n")
  ->Array.mapWithIndex((line, index) =>
    switch from->RegExp.exec(line)->Option.map(RegExp.Result.matches) {
    | Some([Some(image), name]) =>
      let head = image->String.split("$")->Array.getUnsafe(0)
      let stage =
        image->String.includes("$")
          ? head != "" && stages->Array.some(known => known->String.startsWith(head))
          : stages->Array.includes(image)
      name->Option.forEach(name => stages->Array.push(name))
      image == "scratch" || stage || digest->RegExp.test(image)
        ? None
        : Some(`${file}:${Int.toString(index + 1)}: ${image} is not pinned by its tag and a digest`)
    | _ => None
    }
  )
  ->Array.filterMap(found => found)
}

let dockerfile = path => {
  let name = Node.basename(path)
  name == "Dockerfile" ||
  name->String.startsWith("Dockerfile.") ||
  name->String.endsWith(".Dockerfile")
}

/** A pnpm repository's release age, over the tracked `paths`. */
let ages = (~root, ~paths: array<string>): array<string> =>
  paths->Array.includes("pnpm-lock.yaml") && paths->Array.includes("package.json")
    ? releaseAge(
        paths->Array.includes("pnpm-workspace.yaml")
          ? Some(Node.readFileSync(Node.join([root, "pnpm-workspace.yaml"])))
          : None,
      )->Option.mapOr([], why => [why])
    : []

/** Every Dockerfile's base images, over the tracked `paths`. */
let bases = (~root, ~paths: array<string>): array<string> =>
  paths
  ->Array.filter(path => dockerfile(path) && !vendored(path))
  ->Array.flatMap(path => images(Node.readFileSync(Node.join([root, path])), ~file=path))
