/**
 * An RFC's file name, `<yyyy>-<mmdd>-<nn>-<slug>-<id>.md`, the day it was written, its place in
 * that day, a slug for people and an id for machines. RFC 2ut6h.
 */
type t = {day: string, order: int, slug: string, id: string}

/** An area's directory. */
let area = /^[a-z][a-z0-9-]*$/
/** Words in lowercase, joined by single hyphens. */
let slug = /^[a-z0-9]+(?:-[a-z0-9]+)*$/
/** Five of `[a-z0-9]`, unique in its id space and never changed. */
let id = /^[a-z0-9]{5}$/

let alphabet = "abcdefghijklmnopqrstuvwxyz0123456789"

let pad = value => Int.toString(value)->String.padStart(2, "0")

let isDay = (year, month, date) => {
  let made = Date.makeWithYMD(~year, ~month=month - 1, ~day=date)
  made->Date.getMonth == month - 1 && made->Date.getDate == date
}

/** A file's name read, or None where it is not one; `day` is `yyyy-mmdd`. */
let parse = (file): option<t> =>
  switch /^(\d{4})-(\d{2})(\d{2})-(\d{2})-([a-z0-9]+(?:-[a-z0-9]+)*)-([a-z0-9]{5})\.md$/->RegExp.exec(
    file,
  ) {
  | Some(result) =>
    switch result->RegExp.Result.matches {
    | [Some(year), Some(month), Some(date), Some(order), Some(slug), Some(id)] =>
      let number = text => text->Int.fromString->Option.getOr(0)
      isDay(number(year), number(month), number(date)) && number(order) >= 1
        ? Some({day: `${year}-${month}${date}`, order: number(order), slug, id})
        : None
    | _ => None
    }
  | None => None
  }

let format = ({day, order, slug, id}: t) => `${day}-${pad(order)}-${slug}-${id}.md`

/** Where a name stands among every other, `yyyy-mmdd-nn`. */
let place = (day, order) => `${day}-${pad(order)}`

/** A name's words in lowercase, joined by hyphens, `RFC Format` being `rfc-format`. */
let slugOf = name =>
  name
  ->String.toLowerCase
  ->String.replaceRegExp(/[^a-z0-9]+/g, "-")
  ->String.replaceRegExp(/^-|-$/g, "")

/** The day in the writer's own time zone, as a file names it. */
let today = () => {
  let now = Date.make()
  `${Int.toString(now->Date.getFullYear)}-${pad(now->Date.getMonth + 1)}${pad(now->Date.getDate)}`
}

type bytes
@new external bytes: int => bytes = "Uint8Array"
@val external fill: bytes => bytes = "crypto.getRandomValues"
@get_index external byteAt: (bytes, int) => int = ""

/** A random byte, as the system's generator draws one. */
let randomByte = () => fill(bytes(1))->byteAt(0)

/** A fresh id none of `taken` holds; a byte past the alphabet's last whole multiple is redrawn. */
let rec fresh = (taken: array<string>, ~random=randomByte) => {
  let size = alphabet->String.length
  let limit = 256 - mod(256, size)
  let drawn = ref("")
  while drawn.contents->String.length < 5 {
    let byte = random()
    if byte < limit {
      drawn := drawn.contents ++ alphabet->String.charAt(mod(byte, size))
    }
  }
  taken->Array.includes(drawn.contents) ? fresh(taken, ~random) : drawn.contents
}
