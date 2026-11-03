type touched =
  | Every
  | Blocks(array<string>)

let of_ = (~paths as _, ~blocks as _, ~full as _) => Every

let changed = _ => []
