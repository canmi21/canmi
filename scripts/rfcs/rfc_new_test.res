open Testing

let run = args =>
  Node.spawnSync(
    "node",
    Array.concat(
      [Node.join([Registry.root, "scripts/rfcs/rfc_new.res.mjs"]), "new", "--dry-run"],
      args,
    ),
    {encoding: "utf8", timeout: 2000},
  )

describe("rfc new options", () => {
  let status = ["--status", "decided"]
  let into = ["--in", "workspace"]
  [[status], [into], [status, into], [into, status]]->Array.forEach(options => {
    for first in 0 to 1 {
      for second in 0 to options->Array.length == 1 ? 0 : 1 {
        let args = []
        for slot in 0 to 1 {
          if slot == first {
            options[0]->Option.getOrThrow->Array.forEach(arg => args->Array.push(arg))
          }
          if slot == second && options->Array.length == 2 {
            options[1]->Option.getOrThrow->Array.forEach(arg => args->Array.push(arg))
          }
          if slot < 1 {
            args->Array.push("Option Probe")
          }
        }
        test(
          `accepts ${args->Array.join(" ")}`,
          () => {
            let result = run(args)
            // Option values must be removed before counting positional arguments.
            expect(result.status->Nullable.toOption)->toEqual(Some(0))
            expect(result.stdout->Nullable.getOr(""))->toMatch(
              /^would write docs\/rfcs\/\d{4}-\d{4}-option-probe-[a-z0-9]{5}\.md\n/,
            )
          },
        )
      }
    }
  })

  ["--status", "--in", "--day"]->Array.forEach(flag => {
    [[], ["--dry-run"], ["--status", "decided"], ["--in", "workspace"]]->Array.forEach(
      after => {
        let args = Array.concat(["Option Probe", flag], after)
        test(
          `refuses a missing value in ${args->Array.join(" ")}`,
          () => {
            let result = run(args)
            // A missing value must not select a default or consume another flag.
            expect(result.status->Nullable.toOption)->toEqual(Some(2))
            expect(result.stderr->Nullable.getOr(""))->toMatch(/^usage:/)
            expect(result.stdout->Nullable.getOr(""))->toBe("")
          },
        )
      },
    )
  })
})

describe("rfc new name length", () => {
  test("accepts a name of exactly 32 characters", () => {
    let result = run([String.repeat("A", 32)])
    expect(result.status->Nullable.toOption)->toEqual(Some(0))
    expect(result.stdout->Nullable.getOr(""))->toMatch(
      /^would write docs\/rfcs\/\d{4}-\d{4}-a{32}-[a-z0-9]{5}\.md\n/,
    )
    expect(result.stderr->Nullable.getOr(""))->toBe("")
  })

  test("refuses a name of 33 characters with its length and the limit before usage", () => {
    let result = run([String.repeat("A", 33)])
    expect(result.status->Nullable.toOption)->toEqual(Some(2))
    // A name past the limit must explain the refusal before showing usage.
    expect(result.stderr->Nullable.getOr(""))->toMatch(
      /^the name holds 33 characters, more than the 32 allowed\nusage:/,
    )
    expect(result.stdout->Nullable.getOr(""))->toBe("")
  })
})

describe("rfc new placement", () => {
  let place = (~count, ~area) =>
    Rfc_new.placement(~repo="r", ~count, ~area, ~inTree=name => name == "libs")

  test("puts an RFC flat while the repository holds fewer than the widest", () => {
    expect(place(~count=0, ~area=None))->toEqual(Ok(""))
    expect(place(~count=Layout.widest - 1, ~area=None))->toEqual(Ok(""))
  })

  test("refuses an area before the repository is split", () => {
    expect(place(~count=3, ~area=Some("libs")))->toEqual(
      Error("r holds 3 RFCs, at most 16, so they stand flat: give no area"),
    )
  })

  test("refuses a flat repository already at the widest", () => {
    expect(place(~count=Layout.widest, ~area=None))->toEqual(
      Error("r holds 16 RFCs, the most that stand flat: split them into areas of its tree first"),
    )
  })

  test("asks a split repository for an area of its own tree", () => {
    expect(place(~count=Layout.widest + 1, ~area=Some("libs")))->toEqual(Ok("libs"))
    expect(place(~count=Layout.widest + 1, ~area=Some("process")))->toEqual(
      Error("process is no directory of r's own tree"),
    )
    expect(place(~count=Layout.widest + 1, ~area=None))->toEqual(
      Error("r holds more than 16 RFCs, so a new one needs an area of its tree"),
    )
  })
})
