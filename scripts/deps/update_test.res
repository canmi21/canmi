open Testing

describe("Cargo dry reports", () => {
  test("reads actual update and upgrade formats without including headings", () => {
    expect(
      Update.cargoItems("    Updating toml v0.5.10 -> v0.5.11 (available: v1.1.8)", false),
    )->toEqual([Reminder.item("package", "toml", "0.5.10", "0.5.11")])
    expect(
      Update.cargoItems(
        "name old req compatible latest new req\n==== ======= ========== ====== =======\ntoml 0.5     0.5.11     1.1.8  1.1    \n    Checking reminder-fixture's dependencies",
        true,
      ),
    )->toEqual([Reminder.item("major", "toml", "0.5", "1.1")])
    expect(Update.cargoItems("nothing moved", false))->toEqual([])
  })
})
