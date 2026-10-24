// Reads a sed command line as sed reads it, to judge it for a reviewer.

/** The letters a short flag is written with, `-n` as `n`, the long flags left out. */
let letters = flags =>
  flags
  ->Array.filter(flag => !(flag->String.startsWith("--")))
  ->Array.map(flag => flag->String.slice(~start=1))

// The sed short flags that take a value, the rest of the cluster or the next word.
// The l flag takes none on the sed macOS ships, so it is left out.
let valued = ["e", "f"]

/** Where the bracket expression opening at `at` in `chars` ends, past its last `]`. */
let bracketEnd = (chars: array<string>, at) => {
  let length = chars->Array.length
  let char = index => chars[index]->Option.getOr("")
  let next = ref(at + 1)
  if char(next.contents) == "^" {
    next := next.contents + 1
  }
  if char(next.contents) == "]" {
    next := next.contents + 1
  }
  let found = ref(None)
  while found.contents == None && next.contents < length {
    let current = char(next.contents)
    if current == "[" && [":", ".", "="]->Array.includes(char(next.contents + 1)) {
      let close = char(next.contents + 1) ++ "]"
      let stop = ref(next.contents + 2)
      while stop.contents < length && char(stop.contents) ++ char(stop.contents + 1) != close {
        stop := stop.contents + 1
      }
      next := stop.contents + 2
    } else if current == "]" {
      found := Some(next.contents + 1)
    } else {
      next := next.contents + 1
    }
  }
  found.contents->Option.getOr(length)
}

/**
 * Whether a sed script might write a file or run a program, read as sed reads it, refusing what
 * it cannot read.
 */
let writes = (script: string) => {
  let chars = script->Node.codePoints
  let length = chars->Array.length
  let at = ref(0)
  let unsafe = ref(false)
  let char = index => chars[index]->Option.getOr("")
  let isDigit = text => text >= "0" && text <= "9" && text != ""
  let skipDigits = () =>
    while at.contents < length && isDigit(char(at.contents)) {
      at := at.contents + 1
    }
  let skipBlank = () =>
    while char(at.contents) == " " || char(at.contents) == "\t" {
      at := at.contents + 1
    }
  // Moves past one part ending at an unescaped `delimiter`, false where the part is left open.
  let delimited = (delimiter, ~brackets) => {
    let closed = ref(false)
    let going = ref(true)
    while going.contents && at.contents < length {
      let current = char(at.contents)
      if current == "\\" {
        at := at.contents + 2
      } else if current == delimiter {
        at := at.contents + 1
        closed := true
        going := false
      } else if brackets && current == "[" {
        at := bracketEnd(chars, at.contents)
      } else if current == "\n" {
        going := false
      } else {
        at := at.contents + 1
      }
    }
    closed.contents
  }
  let regex = delimiter => {
    if !delimited(delimiter, ~brackets=true) {
      unsafe := true
    }
    while char(at.contents) == "I" || char(at.contents) == "M" {
      at := at.contents + 1
    }
  }
  let address = () =>
    switch char(at.contents) {
    | digit if isDigit(digit) =>
      skipDigits()
      if char(at.contents) == "~" {
        at := at.contents + 1
        skipDigits()
      }
      true
    | "$" =>
      at := at.contents + 1
      true
    | "/" =>
      at := at.contents + 1
      regex("/")
      true
    | "\\" =>
      let delimiter = char(at.contents + 1)
      at := at.contents + 2
      if delimiter == "" || delimiter == "\n" || delimiter == "\\" {
        unsafe := true
      } else {
        regex(delimiter)
      }
      true
    | _ => false
    }
  // Moves to the first of `stops` or the end, a backslash escaping the character after it.
  let skipTo = stops =>
    while at.contents < length && !(stops->Array.includes(char(at.contents))) {
      at := at.contents + (char(at.contents) == "\\" ? 2 : 1)
    }
  let substituted = (~brackets) =>
    switch char(at.contents) {
    | "" | "\n" | "\\" => unsafe := true
    | delimiter =>
      at := at.contents + 1
      if !(delimited(delimiter, ~brackets) && delimited(delimiter, ~brackets=false)) {
        unsafe := true
      }
    }
  while !unsafe.contents && at.contents < length {
    let current = char(at.contents)
    if [" ", "\t", ";", "\n", "}"]->Array.includes(current) {
      at := at.contents + 1
    } else {
      if address() {
        skipBlank()
        if char(at.contents) == "," {
          at := at.contents + 1
          skipBlank()
          if char(at.contents) == "+" || char(at.contents) == "~" {
            at := at.contents + 1
            skipDigits()
          } else if !address() {
            unsafe := true
          }
        }
      }
      skipBlank()
      while char(at.contents) == "!" {
        at := at.contents + 1
        skipBlank()
      }
      let command = char(at.contents)
      at := at.contents + 1
      if unsafe.contents || Delegation.sedWriting->Array.includes(command) {
        unsafe := true
      } else {
        switch command {
        | "{"
        | "="
        | "d"
        | "D"
        | "g"
        | "G"
        | "h"
        | "H"
        | "n"
        | "N"
        | "p"
        | "P"
        | "x"
        | "z"
        | "F" => ()
        | "s" =>
          substituted(~brackets=true)
          let going = ref(true)
          while !unsafe.contents && going.contents && at.contents < length {
            let flag = char(at.contents)
            if [";", "\n", "}"]->Array.includes(flag) {
              going := false
            } else if Delegation.sedWriting->Array.includes(flag) {
              unsafe := true
            } else if (
              isDigit(flag) || ["g", "p", "i", "I", "m", "M", " ", "\t"]->Array.includes(flag)
            ) {
              at := at.contents + 1
            } else {
              unsafe := true
            }
          }
        | "y" => substituted(~brackets=false)
        | "a" | "i" | "c" | "r" | "R" | "#" => skipTo(["\n"])
        | "b" | "t" | "T" | ":" | "v" => skipTo([";", "\n", "}"])
        | "q" | "Q" | "l" | "L" =>
          skipBlank()
          skipDigits()
        | _ => unsafe := true
        }
      }
    }
  }
  unsafe.contents
}

/**
 * Why sed is refused a reviewer, not quiet, in place, given a script file or a script that might
 * write, or none.
 */
let reason = (words: array<string>) => {
  let quiet = ref(false)
  let inPlace = ref(false)
  let fromFile = ref(false)
  let scripts = []
  let operands = []
  let options = ref(true)
  let at = ref(0)
  let valueAfter = () => {
    let value = words[at.contents]
    at := at.contents + 1
    value
  }
  while at.contents < words->Array.length {
    let word = words->Array.getUnsafe(at.contents)
    at := at.contents + 1
    if !options.contents || word == "-" || !(word->String.startsWith("-")) {
      operands->Array.push(word)
    } else if word == "--" {
      options := false
    } else if word->String.startsWith("--") {
      let name = word->String.split("=")->Array.getUnsafe(0)
      let given = word->String.includes("=")
      // sed takes a long flag by any prefix of it, so any prefix of a flag counts.
      let prefixOf = flag => name->String.length >= 3 && flag->String.startsWith(name)
      quiet := quiet.contents || Delegation.sedQuiet->Array.includes(name)
      inPlace :=
        inPlace.contents ||
        Delegation.sedInPlace->Array.some(flag => flag->String.startsWith("--") && prefixOf(flag))
      if prefixOf("--expression") {
        let value = given ? Some(word->String.slice(~start=name->String.length + 1)) : valueAfter()
        value->Option.forEach(value => scripts->Array.push(value))
      } else if prefixOf("--file") {
        fromFile := true
      } else if prefixOf("--line-length") && !given {
        at := at.contents + 1
      }
    } else {
      let chars = word->String.slice(~start=1)->String.split("")
      let scanning = ref(true)
      chars->Array.forEachWithIndex((char, index) =>
        if scanning.contents {
          if valued->Array.includes(char) {
            scanning := false
            let rest = chars->Array.slice(~start=index + 1)->Array.join("")
            let value = rest == "" ? valueAfter() : Some(rest)
            if char == "f" {
              fromFile := true
            } else {
              value->Option.forEach(value => scripts->Array.push(value))
            }
          } else if letters(Delegation.sedQuiet)->Array.includes(char) {
            quiet := true
          } else if letters(Delegation.sedInPlace)->Array.includes(char) {
            inPlace := true
          }
        }
      )
    }
  }
  let script = scripts->Array.length > 0 ? Some(scripts->Array.join("\n")) : operands[0]
  if inPlace.contents {
    Some("sed is never run in place")
  } else if !quiet.contents {
    Some("sed is run only quiet, given -n")
  } else if fromFile.contents {
    Some("sed is never given a script file, which cannot be read here")
  } else if script->Option.mapOr(false, writes) {
    Some(
      `sed is never given a script that might hold ${Delegation.sedWriting->Array.join(
          ", ",
        )} or a command it cannot read`,
    )
  } else {
    None
  }
}
