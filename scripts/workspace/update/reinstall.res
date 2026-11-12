/**
 * Each pnpm lockfile among `paths` installed again where it lies under `repo`, so a move put back
 * leaves no newer copy in node_modules for the next run to read as held.
 */
let after = (repo, paths) =>
  paths
  ->Array.filter(path => Node.basename(path) == "pnpm-lock.yaml")
  ->Array.forEach(path =>
    Node.run(
      ~cwd=Node.join([repo, Node.dirname(path)]),
      "pnpm",
      ["install", "--frozen-lockfile", "--prefer-offline"],
    )->ignore
  )
