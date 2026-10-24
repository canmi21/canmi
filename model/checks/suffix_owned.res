@send external subarray: (Node.bytes, int, int) => Node.bytes = "subarray"
@send external hasByte: (Node.bytes, int) => bool = "includes"

/** Whether the file holds a NUL byte in its first 8000 bytes, as git tells a binary one. */
let binary = path =>
  try Node.readBytes(path)->subarray(0, 8000)->hasByte(0) catch {
  | _ => false
  }

/** Every suffix `root` tracks against `Format.owners` and the repository's own `unformatted`. */
let owned = (~unformatted=[], suffix) =>
  unformatted->Array.includes(suffix) || Format.owners->Array.some(((known, _)) => known == suffix)

/** Each unregistered suffix among `files`, named with one file that has it. */
let problems = (~label, ~unformatted=[], files: array<string>): array<string> => {
  let first = Dict.make()
  files->Array.forEach(file => {
    let suffix = Node.extname(file)
    if suffix != "" && !owned(~unformatted, suffix) && first->Dict.get(suffix) == None {
      first->Dict.set(suffix, file)
    }
  })
  first
  ->Dict.toArray
  ->Array.toSorted(((a, _), (b, _)) => String.compare(a, b))
  ->Array.map(((suffix, file)) =>
    `${label}: ${suffix} has no formatter in Format.owners and is not Unformatted, as ${file}`
  )
}

/** Whether the tracked file at `relative` is read, not vendored, test data or binary. */
let read = (~root, ~format, relative) =>
  !Layout.vendored(relative) &&
  !Project.inTestData(format, relative) &&
  !binary(Node.join([root, relative]))

let main = (~root, ~label): array<string> => {
  let format = Project.formatAt(root)
  Lines.tracked(root)
  ->Array.filter(relative => read(~root, ~format, relative))
  ->problems(~label, ~unformatted=format.unformatted)
}
