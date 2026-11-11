# Pushing

The gate a push passes, what it sets off, and what it must not carry out. Who pushes, and when, is
[commits.md](../commits.md), "When a change is done, and when it is pushed".

## A wave's push passes a gate

**Every push waits on the form layer holding nothing**, in either mode, `push-form-clear`, the last
net after the commit onto a main line refused the same findings, [checking.md](checking.md),
"The form layer holds at gates, never while code is written": the gate
exists so that a debt never outlives the next push, and a session with no role pushing past its
warnings would keep that promise by half. **The gate measures the tree of the commit each pushed
bookmark points to, read from the repository**, never from the disk and never checked out: each such
commit is measured once, a directory's width and depth from `jj file list -r <commit>` and a file's
length and its comments from `jj file show -r <commit>`. A check that refuses reads only what the
repository holds, so its result can be had again, and the working copy is local state. **A push
also replays the `versions` part of the check over its outgoing commits**,
[commits.md](../commits.md), "A package's version rolls at landing".

**An agent pushes only by `mise run push`**, `push-through-verb`, held by `hooks/gates/push.res`: a
`jj git push` or `git push` an agent types is refused before it runs, the body of a quoted
here-document aside, since jj has no push hook and the gate above and the scan below run inside the
verb alone. See [lessons.md](../lessons.md).

**A push that finds the remote's main moved is expected, and nothing to escalate**,
`push-behind-main`. CI commits to main itself, most often the scheduled update moving tools and
dependencies every day, [ci.md](../ci.md). `mise run push` fetches nothing, so a land makes one round trip to the forge: where
`main@origin` as last fetched already holds commits main lacks, it names them and stops with the
steps, and where main moved since, jj refuses the push and the verb says to fetch, read what came
in, rebase onto `main@origin`, check again and push. A land runs no dry push before its push, as
the push passes the same gates first.

**A wave worked in roles also waits on the full check passing, a reviewer having read the wave, and
the wave accepted**, `push-gated`, [checking.md](checking.md), "Acceptance comes before the push". A
session with no role pushes once the check passes and the form layer holds nothing,
[commits.md](../commits.md), "When a change is done, and when it is pushed". **A public repository
also passes the scan for leaks** below; a private one is not scanned.

**monoflake/driver's push releases nothing**: `release.yml` runs by `workflow_dispatch` alone, at the
version in source. An agent dispatches it at one moment, when the author says to move what C has
tested onto A and B: that order is the permission, and the Release is one step of that roll, a
candidate rehearsed, its Release dispatched, then rings and the rest C, B, A. No Release otherwise, and
none in C's loop, monoflake/cloud's RFC stc9g.

**Any other push that releases a version of our own code** is asked of the user first, in either mode,
the deferred item `release-push`, [commits.md](../commits.md), "When a change is done, and when it is
pushed". As things stand, monoflake/platform's, cloud's and driver's pushes run their verify, an
after-the-fact check; every repository's update runs on a daily schedule and by hand, never on a push,
and monoflake/runtime's publish on a push and on a weekly one, and both handle their own edge cases;
and what runtime publishes is an upstream image
repackaged, which [lessons.md](../lessons.md) lets be pushed as it is.

## A repository declares what its push sets off

**Each repository declares, in a `[push]` table of its `workspace.toml`, whether it is public or
private, which CI a push starts, and whether any of it releases a version.** The keys are
`visibility`, `ci`, a list of workflow file names, and `release`, those among them that release. A
workflow under `.github/workflows/` that runs on a push and is not declared there is named. Both
are `push-declared` and `push-workflows-declared` in
[model/rules/toolchain.res](../../model/rules/toolchain.res). **`visibility = "public"` or
`"private"` is read**, by the scan below; a repository declaring none, the workspace itself among
them, is scanned as public. The `push` part of the check holds the table to the workflows, its
findings warnings.

## A push carries nothing private

Three layers.

- **A test and its fixtures use only values reserved for documentation**, the addresses RFCs 5737
  and 3849 reserve and the domains RFC 2606 does, with the address plan the platform's design chose
  allowed beside them, all of it `Toolchain.documentation` in
  [model/rules/toolchain.res](../../model/rules/toolchain.res); and a credential that is plainly a
  placeholder.
- **Before a push, the diff about to go out is scanned** by machine for the private identifiers, for
  the shapes of credentials and strings of high entropy, and for any address or domain written out
  that the allowed list does not hold. A vendor's adapter module is a place a vendor's name may
  stand.
- **A reviewer of a public repository's wave reads its diff for leaks too**,
  [reviewer.md](seats/reviewer.md).

**The private identifiers are listed in a file local to the machine and in no repository**, at
`Toolchain.privateIdentifiers`. The integrator keeps it as a new machine, domain or account comes
in. **A leak the scan finds is also written as a record of friction.** **An integrator's own scan
before a private repository's push counts two groups apart**, the group the list allows in that
repository and every other identifier, printing counts alone: `jj diff --git <paths> | mise run scan
--in <repository>`, where a hit of the repository's group passes and any other stops the push for
the advisor. **The list marks a group by a comment line**, `# allowed in <repository>` as the
registry names it, every entry after it in that group until the next such line; any other line
starting with `#` is a comment. The group allowed in monoflake/cloud is the hostnames differing from
their Network Name, the accounts' identifiers and the retired machine names, its entries kept in the
list alone; `buf` is excluded from the list, as every Rust buffer is named so. A Network Name, a
provider's name and a region's are public and in no group; the author's public handle and the cities
a selfhosted machine's account is named for are exempt and in no list.

**Push scans a public repository twice**. **The lines and the commit messages it sends are refused
on a hit**, each outgoing commit's own lines and message read apart, so one a later commit undoes
still counts, and each identifier matched as a whole word in any case. **Every file it tracks is
scanned too, and a hit there is reported, never refused**: what is already on the remote cannot be
held back by refusing, so the integrator reads each hit and fixes a real leak on the spot. A hit in
what it sends, a line or a commit message, that is no leak, as a field git names alike, passes by
the escape named on the command, `SKIP=scan mise run push ...`, as `SKIP=verify` names a commit's,
and each use is a record of friction naming the word and why it was none.

**An entry of the list may carry its own exceptions**: on its line after it, each after a tab, a
regular expression matched in any case and as a whole word, as the identifier is. A hit inside a
match of one of its exceptions is passed over, and a bare use beside it is still refused; a list
whose exception is no pattern is not read, so no push goes out scanned short. The exceptions stay in
the private file beside their entry, so the scan's code and its tests name no entry of the real list
and no pattern built around one, only made-up ones. An exception is taken over dropping an entry
that a common spelling holds, and over passing that spelling by `SKIP=scan` each time, since a habit
of skipping the scan is the leak to fear.
