# Ship Cloud: the platform, run by its author and used by the author's friends

What the three layers in [layers.md](layers.md) are for, set down on 2026-10-07 because no platform
on offer fits. The author both runs it and uses it, and the two roles are kept apart as strictly
as two strangers' would be.

## Three layers, and what each owns

- **Infra** controls each node and nothing above it: host, keeper, Caddy, the tunnel, the meter,
  the relay, and the node's own API.
- **The platform** joins the nodes and its own services into one set of capabilities, and every
  third party behind them -- Cloudflare's Workers, their bindings, DNS and firewall rules, a
  storage provider, Vercel -- is abstracted here. Deploying a Worker, binding a resource to it,
  pointing a name at it and setting the firewall in front of it are the platform's work, never the
  app's.
- **Services** -- an app -- deals with the platform alone, and never with a provider beside it.

## Tenancy

**A user belongs to several organizations, and sees what they hold.** The author has two: one in
their own name, holding what they deploy as a user, and the platform's, holding the platform
itself. A friend has their own and sees only it. The platform's scope and a user's are two
dimensions of one account, so the author sees both and a friend sees one.

**An organization binds its own accounts**: GitHub, API keys, Cloudflare, Vercel, storage buckets,
and its own machines. What a user deploys goes through those, by the platform's hand.

**Accounts come before anybody else.** The order: the platform made usable for its author, then
accounts, then permission groups that separate the operator from the user -- the author holding
both -- then invitations. There is no public sign-up; the author invites friends.

## Nodes

**A node a friend brings is handed over whole.** It is given by its SSH access or by running the
platform's command on it, which reinstalls the system, joins it to the tailnet and revokes the root
password; from then on the machine is the platform's, not its former owner's. A friend may also
run on nodes the author grants them.

**The control plane runs only on the author's own nodes**, three of them -- the core in infra's
`spec/architecture/nodes.md` -- and a node brought by anybody else is a worker and never more, so
what a former owner could recover from its disk holds no keys to the rest. That, and inviting only
friends, is the whole of the risk taken.

**While nodes are few, one machine carries several roles**, and they separate as nodes are added.
A server's cost is the smallest cost the platform has once it is used, and nothing until then, so
the work now is making it usable, not adding machines that would idle.
