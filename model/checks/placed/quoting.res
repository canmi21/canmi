/** The scanning of a source's comments, quotes, arrays and literals, for `Placed`. */
/** Each match of a global `pattern` in `text`. */
let all = (pattern, text): array<RegExp.Result.t> => {
  let rec next = found =>
    switch pattern->RegExp.exec(text) {
    | Some(result) => next([...found, result])
    | None => found
    }
  next([])
}

/** The line `at` lies on, counted from one. */
let lineOf = (text, at) => text->String.slice(~start=0, ~end=at)->String.split("\n")->Array.length

/** `text` with each comment turned to spaces, its strings and its lines kept where they were. */
let blanked = (text, ~quotes) => {
  let length = text->String.length
  let rec walk = (at, ~quote, ~out) =>
    if at >= length {
      out
    } else {
      let char = text->String.charAt(at)
      let next = text->String.charAt(at + 1)
      switch quote {
      | Some(_) if char == "\\" => walk(at + 2, ~quote, ~out=`${out}${char}${next}`)
      | Some(mark) =>
        let shut = char == mark || (char == "\n" && mark != "`")
        walk(at + 1, ~quote=shut ? None : quote, ~out=`${out}${char}`)
      | None if char == "/" && (next == "/" || next == "*") =>
        let found =
          next == "/" ? text->String.indexOfFrom("\n", at) : text->String.indexOfFrom("*/", at + 2)
        let stop = found < 0 ? length : next == "/" ? found : found + 2
        let spaces = text->String.slice(~start=at, ~end=stop)->String.replaceRegExp(/[^\n]/g, " ")
        walk(stop, ~quote, ~out=`${out}${spaces}`)
      | None =>
        let quote = quotes->String.includes(char) ? Some(char) : None
        walk(at + 1, ~quote, ~out=`${out}${char}`)
      }
    }
  walk(0, ~quote=None, ~out="")
}

/** Where the quote closing at `at` opened, read backward. */
let rec quoteStart = (text, at, ~mark) =>
  if at < 0 {
    -1
  } else if text->String.charAt(at) == mark && text->String.charAt(at - 1) != "\\" {
    at
  } else {
    quoteStart(text, at - 1, ~mark)
  }

/** Where the array or list holding `at` opens, if one and not a call or a block holds it. */
let rec opening = (text, at, ~quotes, ~depth=0) =>
  if at < 0 {
    None
  } else {
    let char = text->String.charAt(at)
    if quotes->String.includes(char) {
      opening(text, quoteStart(text, at - 1, ~mark=char) - 1, ~quotes, ~depth)
    } else if "])}"->String.includes(char) {
      opening(text, at - 1, ~quotes, ~depth=depth + 1)
    } else if "[({"->String.includes(char) {
      switch depth {
      | 0 =>
        let listed = char == "{" && at >= 4 && text->String.slice(~start=at - 4, ~end=at) == "list"
        char == "[" || listed ? Some(at) : None
      | _ => opening(text, at - 1, ~quotes, ~depth=depth - 1)
      }
    } else {
      opening(text, at - 1, ~quotes, ~depth)
    }
  }

/** Where the quote opening before `at` closes, read forward. */
let rec quoteEnd = (text, at, ~mark) =>
  if at >= text->String.length {
    at
  } else if text->String.charAt(at) == "\\" {
    quoteEnd(text, at + 2, ~mark)
  } else if text->String.charAt(at) == mark {
    at
  } else {
    quoteEnd(text, at + 1, ~mark)
  }

/** Where the array or list holding `at` closes, at its last bracket. */
let rec closing = (text, at, ~quotes, ~depth=0) =>
  if at >= text->String.length {
    at
  } else {
    let char = text->String.charAt(at)
    if quotes->String.includes(char) {
      closing(text, quoteEnd(text, at + 1, ~mark=char) + 1, ~quotes, ~depth)
    } else if "[({"->String.includes(char) {
      closing(text, at + 1, ~quotes, ~depth=depth + 1)
    } else if "])}"->String.includes(char) {
      depth == 0 ? at : closing(text, at + 1, ~quotes, ~depth=depth - 1)
    } else {
      closing(text, at + 1, ~quotes, ~depth)
    }
  }

/** The elements between `start` and `stop`, split at their own commas, each trimmed. */
let elements = (text, ~start, ~stop, ~quotes): array<string> => {
  let rec walk = (at, ~depth, ~from, ~found) =>
    if at >= stop {
      [...found, text->String.slice(~start=from, ~end=stop)]
    } else {
      let char = text->String.charAt(at)
      if quotes->String.includes(char) {
        walk(quoteEnd(text, at + 1, ~mark=char) + 1, ~depth, ~from, ~found)
      } else if "[({"->String.includes(char) {
        walk(at + 1, ~depth=depth + 1, ~from, ~found)
      } else if "])}"->String.includes(char) {
        walk(at + 1, ~depth=depth - 1, ~from, ~found)
      } else if char == "," && depth == 0 {
        walk(
          at + 1,
          ~depth,
          ~from=at + 1,
          ~found=[...found, text->String.slice(~start=from, ~end=at)],
        )
      } else {
        walk(at + 1, ~depth, ~from, ~found)
      }
    }
  walk(start, ~depth=0, ~from=start, ~found=[])
  ->Array.map(String.trim)
  ->Array.filter(element => element != "")
}

/** The elements of the array or list holding `at` in a blanked source. */
let containerAt = (text, at, ~quotes) =>
  opening(text, at - 1, ~quotes)->Option.map(start =>
    elements(text, ~start=start + 1, ~stop=closing(text, at, ~quotes), ~quotes)
  )

/** Each string literal of a blanked source, by where it opens and what it holds. */
let literals = (text, ~quotes): array<(int, string)> => {
  let rec walk = (at, ~found) =>
    if at >= text->String.length {
      found
    } else {
      let char = text->String.charAt(at)
      if quotes->String.includes(char) {
        let stop = quoteEnd(text, at + 1, ~mark=char)
        walk(stop + 1, ~found=[...found, (at, text->String.slice(~start=at + 1, ~end=stop))])
      } else {
        walk(at + 1, ~found)
      }
    }
  walk(0, ~found=[])
}

/** The quote and the text of an element that is one string literal and nothing more. */
let quoted = element =>
  switch /^([\x22\x27\x60])((?:\\.|(?!\1)[^\\])*)\1$/s->RegExp.exec(element) {
  | Some(result) =>
    switch result->RegExp.Result.matches {
    | [Some(mark), Some(inner)] => Some((mark, inner))
    | _ => None
    }
  | None => None
  }

/** What a literal says, a backtick's with an interpolation saying nothing fixed. */
let fixed = ((mark, inner)) => mark == "`" && inner->String.includes("${") ? None : Some(inner)
