open Testing

describe("a workflow step's name", () => {
  test("reads steps alone and leaves job names and nested names unread", () => {
    let text = `name: workflow
jobs:
  check:
    name: job
    strategy:
      matrix:
        name: matrix
        steps: [{name: matrix step}]
    steps:
      - name: list the machines
        run: echo ready
      - id: install
        name: "install cloud's packages"
        with:
          name: artifact
      - name: List the machines
      - name: ${"$"}{{ matrix.name }}
      - run: |
          name: shell text
      - uses: actions/checkout@main
`
    expect(Step_names.problems(text, ~file="check.yml"))->toEqual([
      `check.yml: step name "list the machines" starts with a lowercase letter`,
      `check.yml: step name "install cloud's packages" starts with a lowercase letter`,
    ])
  })

  test("reads composite actions and quoted flow style names", () => {
    let text = `name: action
inputs:
  name:
    default: input
runs:
  using: composite
  steps: [{name: 'install packages'}, {name: Install packages}]
`
    expect(Step_names.problems(text, ~file="action.yaml"))->toEqual([
      `action.yaml: step name "install packages" starts with a lowercase letter`,
    ])
    expect(Step_names.problems("jobs: [", ~file="broken.yml")->Array.length)->toBe(1)
  })
})
