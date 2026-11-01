/** The names in a repository's code and paths that rules of naming.res keep out, as warnings. */
let found = (~root): array<string> => {
  let paths = Lines.tracked(root)
  Array.concat(Account.main(~root, ~paths), Rebrand.main(~root, ~paths))
}
