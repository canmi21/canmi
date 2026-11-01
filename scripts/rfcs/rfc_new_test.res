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
  let status = ["--status", "accepted"]
  let into = ["--in", "workspace"]
  [[status], [into], [status, into], [into, status]]->Array.forEach(options => {
    for first in 0 to 2 {
      for second in 0 to options->Array.length == 1 ? 0 : 2 {
        let args = []
        for slot in 0 to 2 {
          if slot == first {
            options[0]->Option.getOrThrow->Array.forEach(arg => args->Array.push(arg))
          }
          if slot == second && options->Array.length == 2 {
            options[1]->Option.getOrThrow->Array.forEach(arg => args->Array.push(arg))
          }
          if slot < 2 {
            args->Array.push(slot == 0 ? "Option Probe" : "agents")
          }
        }
        test(
          `accepts ${args->Array.join(" ")}`,
          () => {
            let result = run(args)
            // Option values must be removed before counting positional arguments.
            expect(result.status->Nullable.toOption)->toEqual(Some(0))
            expect(result.stdout->Nullable.getOr(""))->toMatch(
              /^would write docs\/rfcs\/agents\/\d{4}-\d{4}-\d{2}-option-probe-[a-z0-9]{5}\.md\n/,
            )
          },
        )
      }
    }
  })

  ["--status", "--in", "--day"]->Array.forEach(flag => {
    [[], ["--dry-run"], ["--status", "accepted"], ["--in", "workspace"]]->Array.forEach(
      after => {
        let args = Array.concat(["Option Probe", "agents", flag], after)
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
    let result = run([String.repeat("A", 32), "agents"])
    expect(result.status->Nullable.toOption)->toEqual(Some(0))
    expect(result.stdout->Nullable.getOr(""))->toMatch(
      /^would write docs\/rfcs\/agents\/\d{4}-\d{4}-\d{2}-a{32}-[a-z0-9]{5}\.md\n/,
    )
    expect(result.stderr->Nullable.getOr(""))->toBe("")
  })

  test("refuses a name of 33 characters with its length and the limit before usage", () => {
    let result = run([String.repeat("A", 33), "agents"])
    expect(result.status->Nullable.toOption)->toEqual(Some(2))
    // A name past the limit must explain the refusal before showing usage.
    expect(result.stderr->Nullable.getOr(""))->toMatch(
      /^the name holds 33 characters, more than the 32 allowed\nusage:/,
    )
    expect(result.stdout->Nullable.getOr(""))->toBe("")
  })
})
