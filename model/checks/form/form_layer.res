/** The check's form layer, docs/agents/checking.md, warning at a commit and failing at a push. */
let rules = Rules.all->Array.filterMap(rule =>
  rule.layer == Some(Rule.Form) ? Some(rule.name) : None
)

/** The parts holding a rule of the form layer, by their names. */
let parts = Rules.all->Array.reduce([], (found, rule) =>
  switch rule {
  | {layer: Form, held: Check(part)} if !(found->Array.includes(part)) => [...found, part]
  | _ => found
  }
)

let holds = name => rules->Array.includes(name)

/** Whether a warning of the form layer fails here, under AUDIT or before a push. */
let fails = (~pushing) => pushing || Node.envIs("AUDIT", "1")

/** A part's finding by the rule it breaks, and since when it has, read only when shown. */
type finding = {rule: string, says: string, onset: unit => option<Onset.t>}

/** What a finding says, a form finding with the commit it first appeared in. */
let shown = finding =>
  holds(finding.rule) ? finding.says ++ Onset.said(finding.onset()) : finding.says
