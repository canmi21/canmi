# What goes in an address, and where

Every request says four things, and each has one place. A page and an API divide them the same way:
the rule is about what a part of the request means, not about whether a person or a program reads
the answer.

| Part   | Holds                                           | Removing it                         |
| ------ | ----------------------------------------------- | ----------------------------------- |
| path   | which thing                                     | asks for a different thing, or none |
| query  | which part of it, or in what form               | asks for the same thing, by default |
| body   | what is to change                               | there is nothing to write           |
| header | how the request is made -- credentials, formats | the same thing, asked another way   |

## The path names the thing

**A part that says which thing is asked for is in the path.** An article's slug, a task's id, a
service's name, an object's content id: take one away and the request is about something else, or
about nothing. A thing in a collection is the collection's plural noun, then its id --
`/tasks/{id}`, `/articles/{slug}/likes` -- and a path holds no verb: what is done to the thing is
the method.

**What a page looks like is not the test.** Every article is laid out the same and differs only in
what it says, and its slug is still in its path, because each article is a thing of its own. A
layout changing usually means a different thing is asked for, which is why the two are easy to
confuse; the thing is what decides.

## The query adjusts it

**A part that is optional, has a default and could come in any order is in the query.** A filter,
a range of time, a page of results, an order, a grain, a language, a search's terms: each asks for
the same thing, narrowed or shown another way. `/search?q=` is one thing, the search, asked about
different words; searching photos rather than articles is a different thing, `/search/photos?q=`.

**A lookup takes its inputs in the query.** Where the thing is a computation -- an address from a
latitude and a longitude -- the inputs name nothing that exists before they are asked about, so they
adjust the one thing, the lookup, rather than naming a thing of their own.

**A required parameter in the query is a thing in the wrong place**, unless the route is a lookup.

## An API spells its names out; a page may be short

**A parameter or a key an API takes is written in full** -- `locale`, `latitude`, `resource` --
since a program's caller reads it once and keeps it. **A page's own query is read by people**, in
a link they share or type, and may be short: `?lang=`, `?ref=`. The page is the site asking its
API on a reader's behalf; what it takes from its address it hands on under the API's full names.

## A secret or a person's data is never in an address

**What names a person, or proves who they are, goes in the body even where it is the thing**:
an email address, a token, a code. An address is written into logs, kept by caches and sent on in
`Referer`, and nothing of a person belongs in any of them. Cancelling a subscription names the
subscription by its email and its token, in the body of the `DELETE`, not in its path.

## The body changes it, and a GET never does

**What is written is in the body, sent by the method that says what the write is** -- `POST` to add
to a collection, `PUT` to set, `DELETE` to remove. **A `GET` changes nothing**: a crawler, a
prefetch and every cache on the way may send one at any time, and a request that wrote would be
made by somebody who never asked it to be.

## A header says how the request is made

Credentials, the formats a client accepts, what a cache may do: these are about the exchange, not
the thing, and two requests that differ only in them ask for the same thing. A version is the
exception: it is in the path, where every layer -- a cache's key, a firewall, a log, a reader --
sees it without parsing anything.

## Every URL is declared once

The address packages are the only place a URL, hostname, or dev port may be written down:
`@canmi/me/urls` (crate `canmi`) for the author's own and the world's, `@monoflake/urls` for infra's
and `@monoflake/sdk` for the platform's, each declaring what its owner owns -- see the workspace's `spec/architecture/layers.md`, "Addresses
are split by who owns the name". Everything else imports from them, and above infra from the sdk,
which composes the three into one map. This covers third-party endpoints too, not just our own
hosts -- a CDN we forward images through is as much a URL as a domain we own.

The composed map is grouped by role:

- `apps`: every deployable app of the system, the site's and the platform's, with development and
  production entries.
- `internal`: domains the owner controls that are not apps.
- `external`: third-party endpoints and hostnames.

**The test: who resolves this URL?**

- _The software_ -- it is fetched, linked against, or served from. It goes in its owner's address
  package, with
  no exceptions for app code, libraries, stylesheets, or config.
- _A person reading_ -- a link to a standard, a `# see <url>` note. It stays where it is useful.
  Nothing breaks if it rots except somebody's curiosity.

The earlier version of this rule banned every `https://` outside the library, full stop. That
was wrong on the day it was written: this spec cites four external standards, so the rule was
already broken four times by the document stating it. A rule nobody can follow is not a strict
rule, it is a dead one -- it gets ignored wholesale rather than in the one place it should be.

An identity is not an address. A social handle, an email local part, a feed's tag URI --
these say who someone is, and they live in `site.config.yaml` beside the author's name. What
the address packages own is where to reach them. The two compose: `URLS.external.social.x` plus the
handle is the profile URL, assembled at the point of use rather than stored a second time as
a whole. Putting the handle in the URL library would make the library the owner of a fact
about a person, and the config the owner of nothing.

Names RFC 2606 reserves -- `.test`, `.example`, `.invalid`, `.localhost`, `example.com` and
its siblings -- are exempt as well, and for a stronger reason than convention: the standard
guarantees they never resolve. A placeholder an API needs because it demands an absolute URL,
or a hostname a test supplies precisely so it gets rejected, cannot become a real endpoint by
accident. Exempting them as a class is what stops the check from accumulating one-off
exceptions.

`mise run refs` enforces the first case and skips the second, treating comments, markdown
links, and `$schema` keys as citations. `$schema` has to be a URL precisely because these tools
come from mise and there is no `node_modules` to point at -- see [toolchain.md](toolchain.md). JSON-LD `@context` values and XML namespaces are exempt for a
different reason: each is a namespace identifier, not an endpoint -- changing one changes what
the document means rather than where anything points.

Generated dependency lockfiles are vendor metadata, not an application address source. A package
manager may copy a dependency's deprecation or funding URL into `pnpm-lock.yaml`; the software does
not resolve it, and the next install owns that line. The reference check therefore skips the
lockfile rather than asking an address package to duplicate metadata no repository here controls.

The measure this exists to protect: **moving a domain costs one edit to one file.** Every
literal written elsewhere adds one more place that has to be found, and the ones that get
missed do not fail loudly -- they keep resolving to the old host until someone notices the
traffic. This has already happened once, in web: a `cdn.canmi.net` literal survived inside a
library long after that host stopped being part of the URL map, invisible because nothing
referenced it by name.

**Rust reads the map through a generated mirror.** A Rust process cannot import a TypeScript
library, so each owner renders its own: the platform's `mise run urls` writes its `libs/sdk/src/lib.rs`,
the `monoflake` crate, and the lib repository's writes the `canmi` crate, which infra reads since
it may not read the platform's; web's `local` reads both from crates.io. Each is committed beside
its map, so a checkout compiles without Node having run first. A mirror is never edited by hand:
each package's `rust.test.ts` fails its `verify` the moment it disagrees with its map, so the
one-edit measure survives the language boundary. The
alternative, exempting Rust from the rule, would have left half the repo carrying literals
that the check answers for everywhere else.

### What the reference check will not flag

Path-shaped strings in prose are ignored on purpose. These documents use invented names as
examples -- `apps/r2`, `user-profile.ts`, `libs/canvas` as a name that was rejected -- and a
check that flagged those would be wrong far more often than right.

The convention is what makes the distinction mechanical rather than a judgment the checker has
to make: an illustration stays in inline code, a real reference is a markdown link. So the
check reads links and leaves backticks alone, and neither half has to guess.
