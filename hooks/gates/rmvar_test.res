open Testing

let payload = (~tool="Bash", command): Payload.t =>
  Dict.fromArray([
    ("tool_name", JSON.String(tool)),
    ("tool_input", JSON.Object(Dict.fromArray([("command", JSON.String(command))]))),
  ])

describe("rm variable paths", () => {
  test("refuses unguarded variables in each rm path", () => {
    [
      "rm -rf $S/run-* $S/*.result",
      "rm $S/x",
      "rm -f \"$S\"/x",
      "rm -- ${S}/x",
      "rm $S/*.y",
      "rm -rf /tmp/prefix-$S/x",
      "echo ready; rm -f $S/x",
      "true && rm -f $S/x",
      "true || rm -f $S/x",
      "printf x | rm -f $S/x",
      "sh -c 'rm -rf $S/x'",
      "bash -lc 'echo ready; rm \"$S\"/x'",
      "rm -f $S/x &",
      "(rm -f $S/x; echo done) &",
      "for f in $L; do rm -- $f; done",
      "echo $(rm -f $S/x)",
      "command /bin/rm -f ${S:-}/x",
      "rm -- -$S",
      "rm ${S:?}/$T",
      "rm \"prefix'$S'\"",
    ]->Array.forEach(command => expect((command, Rmvar.unsafe(command)))->toEqual((command, true)))
  })

  test("allows guarded variables, literal paths, and text that is not run", () => {
    [
      "rm ${S:?}/x",
      "rm \"${S:?}\"/x",
      "rm -rf \"${S:?}\"/run-* \"${S:?}\"/*.result",
      "rm -f /tmp/example /tmp/*.result",
      "rm '$S/x'",
      "rm \\$S/x",
      "rm \"\\$S/x\"",
      "echo 'rm -rf $S/x'",
      "echo \"rm -rf $S/x\"",
      "jj commit -m 'fix: rm -rf $S/x'",
      "for f in $L; do rm -- \"${f:?}\"; done",
      "sh -c 'rm \"${S:?}\"/x'",
      "cat <<'EOF'\nrm -rf $S/x\nEOF",
      "printf '%s' $S; rm /tmp/example",
      "rm /tmp/example > $LOG",
    ]->Array.forEach(command => expect((command, Rmvar.unsafe(command)))->toEqual((command, false)))
  })

  test("refuses Bash calls and leaves other tools alone", () => {
    expect(Rmvar.refuse(payload("rm -rf $S/run-* $S/*.result")))->toEqual(2)
    expect(Rmvar.refuse(payload("rm -rf \"${S:?}\"/run-* \"${S:?}\"/*.result")))->toEqual(0)
    expect(Rmvar.refuse(payload(~tool="Write", "rm $S/x")))->toEqual(0)
  })
})
