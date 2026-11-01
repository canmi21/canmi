open Testing

let push = (~stated=true, ~ci=Some([]), ~release=[]): Project.push => {
  visibility: "public",
  stated,
  ci,
  release,
}

describe("a repository's workflows against its [push]", () => {
  test("reads the event as a name, a list or a table", () => {
    expect(Declared_push.runsOnPush("on: push\njobs: {}\n"))->toBe(true)
    expect(Declared_push.runsOnPush("on: [push, pull_request]\n"))->toBe(true)
    expect(Declared_push.runsOnPush("on:\n  push:\n    branches: [main]\n"))->toBe(true)
    expect(Declared_push.runsOnPush("on:\n  schedule:\n    - cron: '0 0 * * *'\n"))->toBe(false)
    expect(Declared_push.runsOnPush("on: workflow_call\n"))->toBe(false)
  })

  test("names a workflow on a push that is not declared", () => {
    expect(
      Declared_push.problems(
        ~push=push(),
        ~workflows=[("verify.yml", true), ("update.yml", false)],
      ),
    )->toEqual(["verify.yml runs on a push and is not declared under [push]"])
    expect(
      Declared_push.problems(
        ~push=push(~ci=Some(["verify.yml"])),
        ~workflows=[("verify.yml", true)],
      ),
    )->toEqual([])
  })

  test("takes a release workflow as declared", () => {
    expect(
      Declared_push.problems(
        ~push=push(~release=["publish.yml"]),
        ~workflows=[("publish.yml", true)],
      ),
    )->toEqual([])
  })

  test("names a declared file that is none, or that does not run on a push", () => {
    expect(
      Declared_push.problems(
        ~push=push(~ci=Some(["a.yml", "b.yml"])),
        ~workflows=[("b.yml", false)],
      ),
    )->toEqual([
      "[push] names a.yml, which is no workflow",
      "[push] ci names b.yml, which does not run on a push",
    ])
  })

  test("asks for the visibility and the ci to be given", () => {
    expect(Declared_push.problems(~push=push(~stated=false, ~ci=None), ~workflows=[]))->toEqual([
      "[push] gives no visibility",
      "[push] gives no ci, the workflows a push starts",
    ])
  })
})
