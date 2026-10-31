/** What is decided and waits, `docs/planning.md`, each item listed at the end of every check. */
type until =
  /** Due once the RFC of this id is landed or declined. */
  | Closes(string)
  /** Due when the author says. */
  | Author

type item = {
  id: string,
  what: string,
  /** Repositories by their path in repos/registry.toml, or `workspace`. */
  repos: array<string>,
  until: until,
  /** The workspace's rules not held over `repos` while the item waits. */
  waives?: array<string>,
  /** `check --all` and `audit --all` pass over `repos` while the item waits. */
  pauses?: bool,
}

let items: array<item> = [
  {
    id: "inline-data-path",
    what: "driver(cloudflare)'s deploy gives a Worker bindings to what the same binding holds, as a service binding to the driver's own object Worker, as the control compiles each call's paths fewest jumps first, a machine's equivalent its loopback, so the data plane on a Cloudflare account is inlined inside Cloudflare and never crosses the control or the public network, RFCs vr5lw and 94y0d and monoflake/driver's nrs5v; its machine half, a deployment reaching the deployments of its own binding it declares, is under way since 2026-10-24 for the component test bench, and its Cloudflare half waits until the products land, or the advisor judges the moment right",
    repos: ["monoflake/platform", "monoflake/driver"],
    until: Author,
  },
  {
    id: "bench-footing",
    what: "monoflake/platform's test bench stands in for the footing, answering a bundle's read alone, RFC 9bq0y; retired once the footing and its samples land, RFC n8jq5, when the issuer's run reads the real footing and the stand-in is deleted",
    repos: ["monoflake/platform"],
    until: Author,
  },
  {
    id: "d1-per-item",
    what: "driver(cloudflare) gives each database item a D1 of its own, made for it and removed with it, replacing the one database and its clearing lease, monoflake/driver's RFC nrs5v, once database is first offered on a Cloudflare binding; it also ends install refusing over a forged `install` table in a user D1",
    repos: ["monoflake/driver"],
    until: Author,
  },
  {
    id: "release-push",
    what: "a push that releases a version of our own code is given whatever further gate it needs once the first such push comes, docs/agents/pushing.md",
    repos: ["workspace"],
    until: Author,
  },
  {
    id: "task-names-nested-rest",
    what: "canmi/web's and seam's mise tasks renamed by task-nested, one word with each action its first argument, the check warning there until then, as the author decided on 2026-10-26",
    repos: ["canmi/web", "seam"],
    until: Author,
  },
  {
    id: "driver-lock-reset",
    what: "monoflake/machine's system/containers/manifest.lock keeps its driver-machine entry, and machine.driver its package path, for the frozen machines that still take the released driver that way, while a machine on the driver's channel takes it from its signed driver pointer, RFC oej2a item 6; both go once every machine is on the channel after step 5's reset, beside the old cache code, as the advisor decided on 2026-10-30, platforms A and B then following GitHub Releases through their own rings while the test platform's ring also takes builds of unreleased code, as the author decided that day",
    repos: ["monoflake/machine", "monoflake/cloud"],
    until: Author,
  },
  {
    id: "nudge-key",
    what: "the author's nudge key, made on 2026-10-30 and named in monoflake/cloud's okra configuration, carries expiry-time 20291030Z in the nudge account's authorized key, so sshd refuses it from 2029-10-30 UTC; the author makes a new one before then and the integrator enters its public half and the new expiry as this one was",
    repos: ["monoflake/cloud", "monoflake/machine"],
    until: Author,
  },
  {
    id: "web-secrets-tasks",
    what: "canmi/web's mise.toml loads secrets.json in its global [env], which `secrets-per-task` forbids since the exposure of 2026-10-29, so it moves into the tasks that use a credential when web's held-back work is next taken up, the tasks check warning there until then, provisional, chosen by the advisor on 2026-10-29",
    repos: ["canmi/web"],
    until: Author,
  },
  {
    id: "paused",
    what: "only the workspace and monoflake are worked on, so every other repository is passed over by every verb run with --all but pull and push",
    repos: [
      "canmi/web",
      "canmi/lib",
      "canmi/rfcs",
      "seam",
      "apps/rdm",
      "apps/cue",
      "apps/still",
      "console",
    ],
    until: Author,
    pauses: true,
  },
  {
    id: "ci-scripts-beside",
    what: "each paused repository's scripts read once it is worked on again, and one only its own CI runs moved under its .github/ beside the workflow, as rdm's pkgs/package.sh, docs/repos.md",
    repos: ["canmi/web", "canmi/lib", "apps/rdm", "apps/cue"],
    until: Author,
  },
  {
    id: "rdm-machine-names",
    what: "apps/rdm's release assets named by the machine as uname -m prints it, rdm-nightly-linux-x86_64 and rdm-nightly-macos-aarch64 rather than x64 and arm64, docs/naming.md's rule for a release asset, once rdm is worked on again",
    repos: ["apps/rdm"],
    until: Author,
  },
  {
    id: "machine-extlinux-board",
    what: "monoflake/machine learns a board U-Boot boots from extlinux with two disks, so the overrides in monoflake/cloud's board.nix for its one such machine move into the module: a small ext4 /boot and a btrfs /cold on its UFS, a 5 GB ext4 / and a btrfs /data with simple quotas on its NVMe, small partitions ext4 and large ones btrfs as decided by the author on 2026-10-25, its serial console named by the board",
    repos: ["monoflake/machine", "monoflake/cloud"],
    until: Author,
  },
  {
    id: "builder-lock-rest",
    what: "monoflake/machine's builder lock, after its review of 2026-10-25, leaves: callers that reuse the builder hold no lock, so `builder up` remakes a stale one under a copy; a changed entry.sh is not seen as stale; the piped tasks' freshness check covers cloud's scripts and not machine's Builder; taking over a dead holder's lock is not atomic; a holder killed before writing its pid, or a reused pid, leaves a lock nobody takes over; the keys read depend on SSH_AUTH_SOCK, so a shell without an agent sees the builder as stale; the lock lives in the user's TMPDIR; a waiter prints nothing",
    repos: ["monoflake/machine", "monoflake/cloud"],
    until: Author,
  },
  {
    id: "cache-rest",
    what: "monoflake/machine's cache, after its review of 2026-10-25, leaves: a small machine's daily garbage collection can delete a path between its builder's query and its fetch, so the fetch lacks it; two builders' sweeps can race on one bucket; R2's answer to a missing pointer, read on the first live run of 2026-10-26, is 404 over S3 and empty output with exit 0 through rclone cat, which the sweep and the fetch now both handle",
    repos: ["monoflake/machine"],
    until: Author,
  },
  {
    id: "cache-lookup-cost",
    what: "monoflake/machine's cache looks its paths up in R2 one narinfo at a time, an rclone cat each: a builder's run upgrading itself on 2026-10-27 took 49 minutes of wall clock for 7.6 of CPU, found at 26 minutes still reading narinfo after narinfo, and a builder's run for another machine that day reached its start timeout at 50 minutes; the lookup's cost is measured and cut",
    repos: ["monoflake/machine"],
    until: Author,
  },
  {
    id: "d1-rows-weekly",
    what: "a weekly read of the controls' D1 rows read per query, through Cloudflare's GraphQL analytics, flagging any query above about 1000 rows an execution, the fourth measure after the address allocation's cost of 2026-10-27, the other three a budget in monoflake/platform's model, a rule in its docs/code.md and an item in every review",
    repos: ["monoflake/platform", "monoflake/cloud"],
    until: Author,
  },
  {
    id: "control-binding-scans",
    what: "monoflake/platform's control reads every binding row for three statements, storage, addressed_at and routed, and its address allocation reads 327,681 rows at full occupancy against the old statement's 262,146, measured through local D1 by lane 18 on 2026-10-27; a migration adds an index on binding's address and on its bound, and allocate_address finds the first gap through the address index, each budget in monoflake/platform's model/rules/control_sql.res lowered to what it then reads, provisional, chosen by the advisor on 2026-10-27",
    repos: ["monoflake/platform"],
    until: Author,
  },
  {
    id: "domain-proof",
    what: "monoflake/platform's control proves an organization holds a domain an app declares as its ingress before the gateway carries it, by RFC vr5lw's TXT record, CNAME or HTTP challenge; until then a declared domain is taken by the first live app that declares it, and only names the author binds to the gateway Worker by hand reach the gateway at all, RFC oomwh, provisional, chosen by the advisor on 2026-10-27",
    repos: ["monoflake/platform"],
    until: Author,
  },
  {
    id: "cache-missed-slot",
    what: "monoflake/machine's cache ends a run that misses its slot, started late, as a failed unit, though missing it is the intended result; a missed slot ends as a skip",
    repos: ["monoflake/machine"],
    until: Author,
  },
  {
    id: "binding-hex-rest",
    what: "after the binding hex wave of 2026-10-25: a binding made before it whose last container item goes names its next one in hex, its images left in its decimal namespace; the decimal token id is parsed four times, in conform, lose, replace and deploy, where the ids library could hold it once",
    repos: ["monoflake/driver", "monoflake/platform"],
    until: Author,
  },
  {
    id: "retire-deploy-race",
    what: "monoflake/platform's control removes a retired app's rows unconditionally once its driver answered the deployment gone, so a deploy of the same app racing the retire, its row written before the removal and its driver call arriving after the delete, leaves a container running with no row; both calls are the operator's alone, so the race needs the operator racing themselves; on the D1 state it closes by a per-app lease, a conditional insert with an expiry answered `held`, taken by deploy and retire alike, once any caller besides the operator may deploy or retire; on the objects state it is the cross-isolate gap of objects-draw-conditional and retires with the production platform at RFC 8yl4b, provisional, chosen by the advisor on 2026-10-25",
    repos: ["monoflake/platform"],
    until: Author,
  },
  {
    id: "deploy-move-stops-old",
    what: "monoflake/platform's control moves an app to another binding by rewriting its deployment row and never stops its container on the old binding, and retire stops only on the binding the row names, so the old container runs on with no row; until a deploy that moves an app stops it on the old binding first, moving an app across bindings is done by hand as a retire, which stops it where it runs, and a deploy under a new id, provisional, chosen by the advisor on 2026-10-25",
    repos: ["monoflake/platform"],
    until: Author,
  },
  {
    id: "objects-draw-conditional",
    what: "monoflake/platform's control on its objects state draws an app's id serialized per isolate rather than by a conditional insert across requests, against RFC b8f35, odds about one in 2^32, and its forget deletes unconditionally, so a deploy in another request can declare between its read and its deletes and run an app the control has forgotten; both retire with the production platform at RFC 8yl4b, when the footing rebuilds it",
    repos: ["monoflake/platform"],
    until: Author,
  },
  {
    id: "tool-ids-module",
    what: "monoflake/platform's deploy, conform, replace and lose each carry a near identical `Ids` module with no interface of the model's, to become one shared module or an interface each, as the author chooses",
    repos: ["monoflake/platform"],
    until: Author,
  },
  {
    id: "machine-system-review",
    what: "monoflake/machine's system reviewed whole and slimmed where it can be -- crun's Python, libkrun, what else a set carries, its criu kept while monoflake/platform's C39 is open -- once monoflake/platform's driver's abilities are built, capability first",
    repos: ["monoflake/machine"],
    until: Author,
  },
  {
    id: "envelope-operations-table",
    what: "envelope generates a table of every operation by its interface and name, its output type among it, and monoflake/platform's runner reads that in place of bindings/generated.res reading the generated module as data",
    repos: ["monoflake/platform"],
    until: Author,
  },
  {
    id: "seam-rfcs",
    what: "seam's RFCs move out of canmi/rfcs into seam's own docs/rfcs",
    repos: ["seam", "canmi/rfcs"],
    until: Author,
  },
  {
    id: "spec-to-docs",
    what: "spec/ is renamed docs/",
    repos: ["canmi/web", "canmi/lib", "apps/rdm", "apps/cue", "seam"],
    until: Author,
    waives: ["rules-in-docs"],
  },
  {
    id: "held-back",
    what: "local commits stay unpushed; a push of canmi/lib publishes packages, so it is asked first",
    repos: ["canmi/web", "canmi/lib", "apps/cue"],
    until: Author,
  },
  {
    id: "machine-platform",
    what: "the machine's option naming the platform it belongs to, one configured value, RFC y6lg7, is added by the first code that reads the name",
    repos: ["monoflake/machine"],
    until: Author,
  },
  {
    id: "cloud-lock-move",
    what: "monoflake/cloud moves its machines' lock to monoflake/machine's newest commit by itself, with a canary first, the author's wish of 2026-10-27; until then the integrator moves it by hand when a change needs testing, each move cleared by the advisor",
    repos: ["monoflake/cloud"],
    until: Author,
  },
  {
    id: "fleet-planned",
    what: "the machines monoflake/cloud keeps under planned/, written but not deployed, are reflashed and moved into machines/ once the author has moved their work off them, their host keys, secrets and cache roles entered then; one already has its peer relay's port open at its provider, the author said on 2026-10-26",
    repos: ["monoflake/cloud"],
    until: Author,
  },
  {
    id: "driver-verify-workflow",
    what: "monoflake/driver runs its verify, the release's version guard among it, in a workflow on every push, so a commit pushed without the local check is still held; until then a lookup that fails warns and passes, provisional, chosen by the advisor on 2026-10-27, its RFC 8c0rg",
    repos: ["monoflake/driver"],
    until: Author,
  },
  {
    id: "mainland-orphan-binding",
    what: "close the binding opened for the mainland consumer on 2026-10-27, 1356310062 (50d7a62e) under monoflake on the foundation platform's control, which no host joined, holding no address and no tunnel, once the control can close bindings; until then it stays, read from its D1 and never deleted by hand",
    repos: ["monoflake/cloud", "monoflake/platform"],
    until: Author,
  },
  {
    id: "test-orphan-binding",
    what: "close the binding the test control opened on 2026-10-29, 4141627861 (f6dc39d5) under the test platform's organization, whose route was refused by the old control's and whose tunnel was deleted by hand, no host joined, once the control can close bindings, monoflake/platform's RFC m2ks6; until then it stays, read from its D1 and never deleted by hand, and the database is not wiped",
    repos: ["monoflake/cloud", "monoflake/platform"],
    until: Author,
  },
  {
    id: "reset-orphan-bindings",
    what: "close the two bindings sora and oak opened on 2026-10-27 under monoflake on the foundation platform's control, sora's 1856388407 (6ea63d37) and oak's 1565746770 (5d536652), and delete their tunnels in its Cloudflare account, left by their reset onto the test platform, at step 5 of monoflake/cloud's RFC oej2a item 8 with A's reset, as the author decided on 2026-10-30, their ids read from each machine's own binding; until then they stay and are never deleted by hand",
    repos: ["monoflake/cloud", "monoflake/platform"],
    until: Author,
  },
  {
    id: "oak-orphan-binding",
    what: "close the binding the test control opened on 2026-10-30, 1110519418 (42312e7a) under the test platform's organization, by oak's reset running bind before its driver was installed, so no host joined it and it holds no address and no tunnel, once the control can close bindings, monoflake/platform's RFC m2ks6; until then it stays, read from its D1 and never deleted by hand",
    repos: ["monoflake/cloud", "monoflake/platform"],
    until: Author,
  },
  {
    id: "driver-release-fixes",
    what: "the four post-release findings of lane 13's third review, a held source still moving its resolved names while its texts say kept, bump inferring a minor from the local platform checkout's contracts rather than the pinned commit, first, a renamed column turning old heads into rows, and a failed read of another day's manifest reddening a released run, as one small lane, provisional, chosen by the advisor on 2026-10-27",
    repos: ["workspace", "monoflake/driver"],
    until: Author,
  },
  {
    id: "operate-retire",
    what: "monoflake/cloud's operate makes a `control:` target whole as though a directory, and monoflake/platform's deploy task declares no --retire and --forget though its tool takes them, so nobody retires or forgets through operate until both are fixed, in lane 9's small fixes, provisional, chosen by the advisor on 2026-10-27",
    repos: ["monoflake/cloud", "monoflake/platform"],
    until: Author,
  },
  {
    id: "driver-binds-domains",
    what: "monoflake/driver's Cloudflare driver binds the domains its apps declare as their ingress by itself, as Custom Domains, where the author binds each by hand today, its token holding Workers Scripts Edit alone; RFC 7dbmi and monoflake/platform's RFC oomwh",
    repos: ["monoflake/driver"],
    until: Author,
  },
  {
    id: "driver-workers-dev",
    what: "monoflake/driver's Cloudflare driver's three Workers, its management, object and database Workers, are reached at their generated addresses today, so `workers_dev` goes false on each once it is reached at a name bound to it, the workspace's custom-domains rule; RFC 7dbmi",
    repos: ["monoflake/driver"],
    until: Author,
  },
  {
    id: "cdn-redirect",
    what: "the Worker cdn-redirect in the monoflake Cloudflare account answers cdn.monoflake.com with a 307 to cdn.ffoni.com and Access-Control-Allow-Origin *, and is deleted only once nothing names cdn.monoflake.com, neither web's own source, by the sdk patch below landing when web unfreezes, nor the published content records, whose favicon and icon addresses still name it; it was deployed by the advisor on 2026-10-28 and is in no repository by design, and its custom domain was bound by the author by hand, as cloud's Cloudflare API token cannot write the zone's routes. After the zone moved canmi.net answered 500, since the site Worker in the canmi account fetches the CDN server-side and that account's Workers still got error 1016 for cdn.monoflake.com from the moved zone, since deleted, while outside requests reached cdn-redirect; at the author's direction the advisor deployed the site as version c6f1d7fa from a scratchpad clone of web's remote main, 2f61940e, with a pnpm patch on @monoflake/sdk@2026.1007.1 setting URLS.apps.production.cdn to https://cdn.ffoni.com, after which canmi.net, /atom.xml and /feed answered 200 on every try, as of 2026-10-29 02:20 UTC. The author decided the patch is not pushed to web's remote, web staying frozen and the fix living in the deployed version alone, so a redeploy from web's main names cdn.monoflake.com again and still works through cdn-redirect, by one more hop. The probe Worker the advisor used to diagnose it is deleted",
    repos: ["canmi/web"],
    until: Author,
  },
  {
    id: "tailscale-token",
    what: "the Tailscale API token in monoflake/cloud's secrets.json, rolled after the exposure of 2026-10-29 and made on 2026-10-30 at 01:07 UTC, expires on 2026-11-29 at 01:07 UTC, the one before it already refused; the author issues the next one before then and the integrator enters it as this one was",
    repos: ["monoflake/cloud"],
    until: Author,
  },
  {
    id: "runner-token",
    what: "the self-hosted runners' token in monoflake/cloud's runner/secrets.json, shared by ci-raleigh, ci-tokyo and ci-sanjose, the fine-grained token ci-runner whose resource owner is the monoflake organization and whose one permission is the organization's Self-hosted runners, read and write, made on 2026-10-30, expires on 2027-10-30; before then the author makes the next one, enters it with `mise run secret monoflake/cloud/runner runner-token`, and runs `mise run runner update`, RFC obvjb",
    repos: ["monoflake/cloud"],
    until: Author,
  },
  {
    id: "reset-rotations",
    what: "monoflake/cloud's secrets.json was exposed on 2026-10-29, and what of A's and B's controls a reset alone leaves valid is replaced at their resets, A's at step 5 of RFC oej2a item 8 and B's at step 6, as the author decided that day: each control's sealing key, never replaced unless exposed as that step says, each one's operator secret, CONTROL_OPERATOR and CONTROL_PRODUCTION_OPERATOR, and A's tunnel token, CONTROL_CLOUDFLARE_TOKEN. Each is typed in by the author through `mise run secret` and put into its control by the integrator; until then each control keeps its own. A's three were typed in by the author on 2026-10-31, CONTROL_OPERATOR and CONTROL_SEALING_KEY as 32 random bytes in unpadded base64url and CONTROL_CLOUDFLARE_TOKEN a new token holding Cloudflare Tunnel Edit alone on the monoflake account, the old token deleted, the author accepting that A's running control refuses the Mac's tools until its reset; what is left of A's is the integrator putting them into A's control at step 5. CLOUDFLARE_API_TOKEN and TAILSCALE_API_TOKEN were rolled by the author on 2026-10-29, each new one verified and each old one refused; the test platform's values and its account's tokens are kept on purpose, the test being the test",
    repos: ["monoflake/cloud"],
    until: Author,
  },
  {
    id: "production-nix-key",
    what: "A's and B's CI signs with one Nix key, `ci<nix@monoflake.com>-1`, its last number counting rotations with both keys trusted while one replaces the other, as the author decided on 2026-10-29, and with one ssh ed25519 pointer key, `ci-pointers`, shared by A and B, as the author decided on 2026-10-31; both were made by the advisor on 2026-10-31 and set as monoflake/cloud's GitHub secrets NIX_SIGNING_KEY and POINTER_SIGNING_KEY, the author's one copy of each in `~/.ssh/monoflake_nix` and `~/.ssh/monoflake_pointer_ed25519` on the Mac, no other kept, a lost key rotated. What is left waits on step 5 of monoflake/cloud's RFC oej2a item 8: the public halves written into monoflake/cloud's config and A's and B's machines as the test platform's were, and the four old builder keys, each named for its builder and ending in -cache-1, removed with the old cache code after that reset",
    repos: ["monoflake/cloud", "monoflake/machine"],
    until: Author,
  },
  {
    id: "stale-lanes",
    what: "the lanes sweep and upgrade under lanes/, left from 2026-10-27 and 10-29 holding work main lacks, are forgotten and removed once the fleet's reset is done, with no bookmark kept, as the author decided on 2026-10-31: sweep's commit 90e2bb0b and its working copy carry the old builders' cache code under monoflake/machine's system/nix/cache, and upgrade's working copy 5709eb5f carries monoflake/cloud's scripts/upgrade.res and its test for the old update mechanism",
    repos: ["monoflake/cloud", "monoflake/machine", "workspace"],
    until: Closes("oej2a"),
  },
  {
    id: "cloud-split",
    what: "monoflake/cloud, which holds the fleet's machines, runners and systems beside the platforms' deployments and one secrets file for all of them, is split into repositories by layer once development is mostly done, when the author judges it, as the author decided on 2026-10-31; until then it stays one repository so a change can cross the layers in one commit",
    repos: ["monoflake/cloud"],
    until: Author,
  },
  {
    id: "console-copy",
    what: "the local copy of console and its registry entry are removed",
    repos: ["console"],
    until: Author,
    waives: ["rules-in-docs"],
  },
]
