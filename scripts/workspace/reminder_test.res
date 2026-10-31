open Testing

let now = Date.fromString("2026-10-31T15:00:00Z")->Date.getTime
let item = kind => Reminder.item(~repository="workspace", kind, "fixture", "1", "2")
let seen = (kind, firstSeen): Reminder.seen => {item: item(kind), firstSeen}

describe("the update reminder", () => {
  test("starts once per UTC calendar day", () => {
    expect(Reminder.due(~now, None))->toBe(true)
    expect(Reminder.due(~now, Some("2026-10-30")))->toBe(true)
    expect(Reminder.due(~now, Some("2026-10-31")))->toBe(false)
    expect(Reminder.due(~now, Some("invalid")))->toBe(true)
  })
  test("reports actions majors and missing installs immediately", () => {
    ["action", "major", "missing"]->Array.forEach(
      kind => expect(Reminder.reported(~now, seen(kind, "2026-10-31")))->toBe(true),
    )
  })
  test("waits more than two calendar days for every scheduled mover", () => {
    ["tool", "package", "image", "release", "flake"]->Array.forEach(
      kind => {
        expect(Reminder.reported(~now, seen(kind, "2026-10-31")))->toBe(false)
        expect(Reminder.reported(~now, seen(kind, "2026-10-30")))->toBe(false)
        expect(Reminder.reported(~now, seen(kind, "2026-10-29")))->toBe(false)
        expect(Reminder.reported(~now, seen(kind, "2026-10-28")))->toBe(true)
        expect(Reminder.reported(~now, seen(kind, "2026-11-01")))->toBe(false)
        expect(Reminder.reported(~now, seen(kind, "invalid")))->toBe(false)
      },
    )
    expect(Reminder.reported(~now, seen("unknown", "2026-10-01")))->toBe(false)
  })
  test("carries the first date only for the same item and drops resolved items", () => {
    let old = seen("package", "2026-10-01")
    let changed = {...old.item, to: "3"}
    let renamed = {...old.item, repository: "monoflake/driver"}
    expect(
      Reminder.carry(
        ~today="2026-10-31",
        [old, seen("action", "2026-10-01")],
        [old.item, changed, renamed],
      ),
    )->toEqual([
      old,
      {item: changed, firstSeen: "2026-10-31"},
      {item: renamed, firstSeen: "2026-10-31"},
    ])
  })
  test("prints ordered counts and stays silent when nothing qualifies", () => {
    expect(Reminder.render(~now, []))->toBe("")
    expect(Reminder.render(~now, [seen("tool", "2026-10-31")]))->toBe("")
    expect(
      Reminder.render(
        ~now,
        [
          seen("missing", "2026-10-31"),
          seen("action", "2026-10-31"),
          seen("action", "2026-10-31"),
          seen("package", "2026-10-28"),
        ],
      ),
    )->toBe("2 action, 1 missing, 1 package; mise run update --dry-run for detail")
  })
  test("round trips the machine summary and rejects malformed items", () => {
    expect(Reminder.decode(Reminder.encode([item("action")])))->toEqual([item("action")])
    expect(Reminder.decode("[{}, null]"))->toEqual([])
  })
})
