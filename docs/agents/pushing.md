# Pushing

The gate a push passes, what it sets off, and what it must not carry out, decided by the author on
2026-10-24. Who pushes, and when, is [commits.md](../commits.md), "When a change is done, and when
it is pushed".

## A wave's push passes a gate

**The push gate holds for a wave worked in roles alone**; a session with no role pushes once the
check passes and the work is done, [commits.md](../commits.md), "When a change is done, and when it
is pushed". **The push gate** is the full check passing, the form layer holding nothing,
[checking.md](checking.md), "The form layer holds at gates, never while code is written", once
`push-gated` lands; a reviewer having read the wave; and the wave accepted,
[checking.md](checking.md), "Acceptance comes before the push". **A public repository also passes
the scan for leaks** below; a private one is not scanned.

**A push that releases a version of our own code** may need a further gate, decided once the first
such push comes, the deferred item `release-push`; until then it is asked of the user first, in
either mode,
[commits.md](../commits.md), "When a change is done, and when it is pushed". As things stand,
monoflake/platform's and monoflake/cloud's pushes start no CI; monoflake/driver's release starts by
hand alone; monoflake/machine's update and monoflake/runtime's publish run on a push and on a daily
schedule, and handle their own edge cases; and what runtime publishes is an upstream image
repackaged, which [lessons.md](../lessons.md) lets be pushed as it is.

## A repository declares what its push sets off

**Each repository declares, in a `[push]` table of its `workspace.toml`, whether it is public or
private, which CI a push starts, and whether any of it releases a version.** A workflow under
`.github/workflows/` that runs on a push and is not declared there is refused. Both are
`push-declared` and `push-workflows-declared` in
[model/rules/toolchain.res](../../model/rules/toolchain.res), pending; the table is not added yet,
since a key no script reads is refused.

## A push carries nothing private

Three layers.

- **A test and its fixtures use only values reserved for documentation**, the addresses RFCs 5737
  and 3849 reserve and the domains RFC 2606 does, with the address plan the platform's design chose
  allowed beside them, all of it `Toolchain.documentation` in
  [model/rules/toolchain.res](../../model/rules/toolchain.res); and a credential that is plainly a
  placeholder.
- **Before a push, the diff about to go out is scanned** by machine for the private identifiers,
  for the shapes of credentials and strings of high entropy, and for any address or domain written
  out that the allowed list does not hold. A vendor's adapter module is a place a vendor's name may
  stand.
- **A reviewer of a public repository's wave reads its diff for leaks too**,
  [reviewer.md](reviewer.md).

**The private identifiers are listed in a file local to the machine and in no repository**, at
`Toolchain.privateIdentifiers`. The integrator keeps it as a new machine, domain or
account comes in. **A leak the scan finds is also written as a record of friction.**
