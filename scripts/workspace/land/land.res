type asked = {
  repository: string,
  subject: string,
  trailers: array<string>,
  paths: array<string>,
  thread: option<string>,
  dry: bool,
}

let parse = _ => Error("land: not written yet")

type step =
  | Format
  | Bump
  | Check
  | Commit
  | Bookmark
  | PushDry
  | Push
  | Record

let steps = [Format, Bump, Check, Commit, Bookmark, PushDry, Push, Record]

let command = (_, _) => ("true", [])

let run = async _ => 1
