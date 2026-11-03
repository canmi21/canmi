/***
 * A seat's time read from its transcript in phases, so the table shows what a seat spends before
 * it writes, docs/agents/briefs.md. The model's interface, `docs/code.md`.
 */

/**
 * A seat's phases in seconds: warm-up from its first line to its first edit, the reads before that
 * edit, editing until its report, the seconds of its own checks within it, and its whole span.
 */
type phases = {
  warmup: float,
  reads: int,
  editing: float,
  checks: float,
  whole: float,
}

/** The phases of a transcript's text, none for a seat that never edited. */
let of_: string => option<phases>
