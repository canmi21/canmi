/** Finds a divider comment and an oxlint directive that gives no reason. */
let directive = /oxlint-disable(?:-next-line|-line)?\s+[\w\/@-]+/
let reasoned = /oxlint-disable[^\n]*\s--\s\S/
let stating = ["model/rules/code.res", "model/checks/notes.res"]

let main = (~root): array<string> =>
  References.tracked(root, ~skipFiles=["pnpm-lock.yaml"])
  ->Array.filter(path =>
    Node.extname(path) != ".md" && !(stating->Array.includes(Node.relative(root, path)))
  )
  ->Array.flatMap(path => {
    let relative = Node.relative(root, path)
    References.read(path)
    ->String.split("\n")
    ->Array.mapWithIndex((line, index) => (index + 1, line))
    ->Array.filterMap(((number, line)) => {
      let at = `${relative}:${Int.toString(number)}`
      if Code.separator->RegExp.test(line) {
        Some(`${at}: a divider; let a module boundary or a name separate it`)
      } else if directive->RegExp.test(line) && !(reasoned->RegExp.test(line)) {
        Some(`${at}: an oxlint directive with no reason after --`)
      } else {
        None
      }
    })
  })
