# Robots and security.txt

**Every public host the author runs answers `robots.txt` and `/.well-known/security.txt`, built
from `@canmi/me/robots` and declared by the repository that builds the host.** The package holds
what every host shares and names none; a repository declares its own hosts -- each one's rules,
its word to an agent, and itself as the source -- and no repository declares another's.

The reason is the source. Each file ends by sending an agent to the code behind the host, and a
policy written in one place for every host named one repository for all of them, which was wrong
for every host built elsewhere. Declared where the host is built, the source is the repository the
declaration sits in, and cannot drift from it.

How the package keeps the rule -- content signals, the sitemaps, the note's layout -- is lib's
`spec/me/robots.md`.
