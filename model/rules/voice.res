/** How what is written into a file reads; the words part reads it. */
/** British spellings, each with the American one that replaces it. */
let british = [
  ("colour", "color"),
  ("behaviour", "behavior"),
  ("licence", "license"),
  ("organisation", "organization"),
  ("organise", "organize"),
  ("favour", "favor"),
  ("honour", "honor"),
  ("centre", "center"),
  ("analyse", "analyze"),
  ("recognise", "recognize"),
  ("initialise", "initialize"),
  ("normalise", "normalize"),
  ("serialise", "serialize"),
  ("optimise", "optimize"),
  ("artefact", "artifact"),
  ("travelled", "traveled"),
  ("cancelled", "canceled"),
  ("labelled", "labeled"),
  ("modelling", "modeling"),
  ("catalogue", "catalog"),
]

/** Shorthand a name is never written in, each with the whole word. */
let shortened = [("CF", "Cloudflare"), ("DB", "database"), ("DBs", "databases")]

/** Text outside English: CJK ideographs, kana, hangul and full-width forms. */
let foreign = RegExp.fromString("[\u3040-\u30ff\u3400-\u9fff\uac00-\ud7af\uff00-\uffef]")

/** Files whose job is to read or measure another language, so they quote it. */
let quoting = ["hooks/language.py", "hooks/test_language.py", "scripts/lints/lints_test.res"]

let doc = "docs/voice.md"
let rules: array<Rule.t> = [
  {
    name: "english-only",
    says: "Everything written into a file is English, outside `quoting`",
    doc,
    held: Check("words"),
  },
  {
    name: "american-spelling",
    says: "The English is American: none of `british`",
    doc,
    held: Check("words"),
  },
  {
    name: "names-whole",
    says: "A name is written whole, never in `shortened`",
    doc: "docs/naming.md",
    held: Check("words"),
  },
  {
    name: "figure-dated",
    says: "A figure describing a state that changes on its own is dated",
    doc,
    held: Pending("telling a figure that changes on its own from a constant the code uses"),
  },
]
