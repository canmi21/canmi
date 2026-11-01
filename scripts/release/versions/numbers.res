/** A package's `major.minor.patch` and what it rolls to, the versions part of the check. */
type t = (int, int, int)

let zero = (0, 0, 0)

/** A version's three numbers, or none where it is not plain `major.minor.patch`. */
let parse = version =>
  if !RegExp.test(/^(0|[1-9][0-9]*)[.](0|[1-9][0-9]*)[.](0|[1-9][0-9]*)$/, version) {
    None
  } else {
    switch version->String.split(".")->Array.map(part => Int.fromString(part)) {
    | [Some(major), Some(minor), Some(patch)] => Some((major, minor, patch))
    | _ => None
    }
  }

let show = ((major, minor, patch)) =>
  `${major->Int.toString}.${minor->Int.toString}.${patch->Int.toString}`

let later = ((a, b, c), (x, y, z)) => a != x ? a > x : b != y ? b > y : c > z

/**
 * What one package's landing asks of its version. `target` is the minor its one interface holds,
 * and `minor` a raise by a breaking change, by judgment, or by one of several interfaces rising.
 */
type asked = {base: option<t>, now: t, changed: bool, target: option<int>, minor: bool}

/** The version a landing owes, computed from its base alone so a second run asks the same. */
let owed = ({base, now, changed, target, minor}) =>
  switch base {
  | None if now != zero => now
  | None | Some((0, 0, 0)) => (0, target->Option.getOr(1), 0)
  | Some((major, was, patch)) =>
    switch target {
    | Some(wanted) if wanted > was => (major, wanted, 0)
    | Some(_) => changed ? (major, was, patch + 1) : (major, was, patch)
    | None if minor => (major, was + 1, 0)
    | None => changed ? (major, was, patch + 1) : (major, was, patch)
    }
  }

/** The higher of what is owed and what is written, so a raise by hand is kept. */
let rolled = asked => {
  let wanted = owed(asked)
  later(asked.now, wanted) ? asked.now : wanted
}

/** Each way a written version breaks what its landing owes, with no words on how to fix it. */
let broken = asked => {
  let wanted = owed(asked)
  let (major, minor, _) = asked.now
  Array.flat([
    later(wanted, asked.now) ? [`stays ${show(asked.now)}, owing ${show(wanted)}`] : [],
    switch asked.base {
    | Some((was, _, _) as base) if was != major => [
        `moves its major from ${show(base)} to ${show(asked.now)}, which only the author moves`,
      ]
    | _ => []
    },
    switch asked.base {
    | Some(base) if later(base, asked.now) && base != zero => [
        `falls from ${show(base)} to ${show(asked.now)}`,
      ]
    | _ => []
    },
    switch asked.target {
    | Some(wanted) if wanted != minor && asked.now != zero => [
        `holds minor ${minor->Int.toString} where its interface is ${wanted->Int.toString}`,
      ]
    | _ => []
    },
  ])
}
