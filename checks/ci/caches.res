/** ci-rust-cache and ci-runner-local, docs/ci.md, "A build's cache follows where it builds". */
open Runs

let mentions = (value, needle) => value->String.includes(needle)

/** Whether a job's runner may be a hosted one, which carries no `self-hosted` label. */
let hosted = job => job.runsOn != "" && !(job.runsOn->mentions("self-hosted"))

/** Whether a job's runner is self-hosted alone, not chosen between that and a hosted label. */
let selfHosted = job =>
  job.runsOn->mentions("self-hosted") &&
    !(["ubuntu", "macos", "windows"]->Array.some(label => job.runsOn->mentions(label)))

let runsCargo = step =>
  step.run->Option.mapOr(false, run =>
    run
    ->commands
    ->Array.some(segment =>
      head(segment) == "cargo" || (head(segment) == "mise" && segment.text->mentions(" rust:"))
    )
  )

let rustCache = "Swatinem/rust-cache@"

/** Whether a step restores cargo's cache, itself or through a local action that does. */
let caches = (step, ~documents: array<document>) =>
  switch step.uses {
  | Some(uses) if uses->String.startsWith(rustCache) => true
  | Some(uses) if uses->String.startsWith("./") =>
    documents->Array.some(document =>
      document.action &&
      uses->String.endsWith(document.file->String.replaceRegExp(/\/action\.ya?ml$/, "")) &&
      document.jobs->Array.some(job =>
        job.steps->Array.some(
          inner => inner.uses->Option.mapOr(false, String.startsWith(_, rustCache)),
        )
      )
    )
  | _ => false
  }

/** What a hosted job running cargo without rust-cache breaks. */
let rustCacheProblems = (documents: array<document>): array<string> =>
  documents->Array.flatMap(document =>
    document.jobs->Array.filterMap(job =>
      hosted(job) &&
      job.steps->Array.some(runsCargo) &&
      !(job.steps->Array.some(step => caches(step, ~documents)))
        ? Some(
            `${document.file}: job ${job.id} runs cargo on a hosted runner without Swatinem/rust-cache`,
          )
        : None
    )
  )

/** The cache a step leaves on, or none where it is off or follows the runner. */
let left = step =>
  switch step.uses {
  | _ if step.condition->mentions("runner.environment") => None
  | Some(uses) if uses->String.startsWith("actions/cache") || uses->String.startsWith(rustCache) =>
    Some(uses)
  | Some(uses)
    if uses->String.startsWith("actions/setup-") && step.inputs->Dict.get("cache") != None =>
    Some(uses)
  | Some(uses) if uses->String.startsWith("jdx/mise-action@") =>
    let value = step.inputs->Dict.get("cache")->Option.mapOr("true", value => JSON.stringify(value))
    ["false", "\"false\""]->Array.includes(value) || value->mentions("runner.environment")
      ? None
      : Some(uses)
  | _ => None
  }

/** What a self-hosted job, or a composite action's mise step, leaving a GitHub cache on breaks. */
let runnerProblems = (documents: array<document>): array<string> =>
  documents->Array.flatMap(document =>
    document.jobs->Array.flatMap(job =>
      job.steps->Array.filterMap(
        step =>
          switch left(step) {
          | Some(uses) if selfHosted(job) =>
            Some(`${document.file}: job ${job.id} keeps ${uses} on a self-hosted runner`)
          | Some(uses) if document.action && uses->String.startsWith("jdx/mise-action@") =>
            Some(`${document.file}: ${uses} caches without following the runner`)
          | _ => None
          },
      )
    )
  )
