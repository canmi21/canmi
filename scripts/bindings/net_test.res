open Testing

describe("a read asked again", () => {
  testAsync("answers the first try that holds, asking no more after it", async () => {
    let tries = ref(0)
    let answer = await Net.retried(
      async () => {
        tries := tries.contents + 1
        tries.contents < 3 ? Error("stalled") : Ok("answered")
      },
    )
    expect(answer)->toEqual(Ok("answered"))
    expect(tries.contents)->toBe(3)
  })

  testAsync("gives up after the first try and two more, saying the last failure", async () => {
    let tries = ref(0)
    let answer = await Net.retried(
      async () => {
        tries := tries.contents + 1
        Error(`stalled ${tries.contents->Int.toString}`)
      },
    )
    expect(answer)->toEqual(Error("stalled 3"))
    expect(tries.contents)->toBe(1 + Net.retries)
  })

  testAsync("asks once where the first try answers", async () => {
    let tries = ref(0)
    let answer = await Net.retried(
      async () => {
        tries := tries.contents + 1
        Ok(1)
      },
    )
    expect(answer)->toEqual(Ok(1))
    expect(tries.contents)->toBe(1)
  })
})

describe("reads asked a few at once", () => {
  testAsync("keeps the items' order and never runs more than the bound", async () => {
    let running = ref(0)
    let widest = ref(0)
    let answers = await Net.bounded(
      [5, 1, 4, 2, 3, 0],
      ~limit=2,
      async delay => {
        running := running.contents + 1
        widest := Math.Int.max(widest.contents, running.contents)
        await Promise.make((resolve, _) => setTimeout(() => resolve(), delay)->ignore)
        running := running.contents - 1
        delay * 10
      },
    )
    expect(answers)->toEqual([50, 10, 40, 20, 30, 0])
    expect(widest.contents)->toBe(2)
  })

  testAsync("answers nothing for nothing", async () => {
    expect(await Net.bounded([], ~limit=4, async item => item))->toEqual([])
  })
})

describe("a read refused for good", () => {
  testAsync("is not asked again where `again` says it would not change", async () => {
    let tries = ref(0)
    let answer = await Net.retried(
      ~again=why => why != "refused",
      async () => {
        tries := tries.contents + 1
        Error("refused")
      },
    )
    expect(answer)->toEqual(Error("refused"))
    expect(tries.contents)->toBe(1)
  })
})
