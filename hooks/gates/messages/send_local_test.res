open Testing

let known: Send_local.known = {
  sessions: ["workspace-87", "monoflake@workspace"],
  subagents: ["a2028374e9bf6e763", "tidy"],
  socket: path => path == "/tmp/cc-socks/47875.sock",
}
let refused = to => Send_local.why(to, ~known) != None

describe("a message", () => {
  test("is let through to what is on this machine", () => {
    [
      "main",
      "workspace-87",
      "monoflake@workspace",
      "workspace-87 [3fa9c1]",
      "a2028374e9bf6e763",
      "tidy",
      "uds:/tmp/cc-socks/47875.sock",
    ]->Array.forEach(to => expect((to, refused(to)))->toEqual((to, false)))
  })

  test("is refused to what is not", () => {
    [
      "made-up",
      "made-up [3fa9c1]",
      "uds:/tmp/cc-socks/1.sock",
      "uds:/elsewhere/47875.sock",
    ]->Array.forEach(to => expect((to, refused(to)))->toEqual((to, true)))
  })

  test("reads a listing's ref off a name", () => {
    expect(Send_local.bare("name [ref]"))->toEqual("name")
    expect(Send_local.bare("name"))->toEqual("name")
  })

  test("takes only a socket in the directory sessions listen in", () => {
    expect(Send_local.localSocket("/elsewhere/a.sock"))->toEqual(false)
    expect(Send_local.localSocket("/tmp/cc-socks/none.sock"))->toEqual(false)
  })
})
