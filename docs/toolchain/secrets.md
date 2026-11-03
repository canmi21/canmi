# Secrets

Credentials live in `secrets.json`, encrypted with [sops](https://getsops.io) to an
[age](https://age-encryption.org) key and **committed that way**. `.sops.yaml` names the recipient
public key, which is safe to commit -- it encrypts and cannot decrypt.

**Only a task that uses a credential decrypts it**: each such task loads the file by an `env = {
_.file = "secrets.json" }` of its own, and a repository's global `[env]` never names it,
`secrets-per-task` in `model/rules/toolchain.res`. The task's tools read the values from its
environment, and nothing keeps a second copy. `secrets-unprinted` refuses a command that prints
credentials only when a subagent runs it, so the file not being loaded is what guards every other
shell and tool. canmi/web still loads its file globally, the deferred item
`web-secrets-tasks`.

The private key lives at `~/.config/sops/age/keys.txt`, outside the repo, and belongs in a password
manager as well. Losing it costs a round of credential rotation, not the repo.

Committing the ciphertext rather than gitignoring a plaintext `.env` is what makes a fresh machine
reproducible: restore one key, clone, and every credential the project needs is already there. A
gitignored `.env` leaves no record of _which_ secrets exist, so setting up again means rediscovering
them one failure at a time.

Only genuinely secret values go in. Facts like `RCLONE_CONFIG_R2_TYPE = "s3"` stay in `mise.toml`,
so a diff of the encrypted file always means a credential actually changed.

**A value the browser must have cannot be a secret.** Anything compiled into a client bundle -- an
analytics token, a Sentry DSN, a publishable API key -- is readable from devtools by anyone who
loads the page. Storing it encrypted does not hide it; it only hides from the reader of this
repository that it is already public. Those go in an address package -- `@canmi/me/urls` holds every
app's Sentry DSN -- or plain config, labeled for what they are.

The same kind of credential can be secret elsewhere. A token a Worker calls another service with
never reaches a browser, so it stays a wrangler secret. What decides is exposure, not the kind of
thing it is.

**A credential is issued only for what runs on a server, in CI or in the cloud; a task that runs
only on the author's Mac uses the author's logged-in CLIs**, `cf`, `wrangler`, `gh` and `tailscale`.
What runs elsewhere holds an account-owned token in the account it acts in, never a user-owned one,
minted by that account's token manager; the author's own login is the one user-level credential
left.

### A secret is typed in, never written down

**A value goes into `secrets.json` by `mise run secret <repo> <NAME>...` and no other way.** It asks
for each name in turn, reads what is typed without echoing it, and hands it to `sops set
--value-stdin`, so the value is in no argument, no process listing, no shell history and no plain
file but the one `--from` below reads it from. A name already set is replaced only when answered
`y`, or without the question under `--replace`, which says the replacement is already decided;
nothing typed leaves it as it was. It reports each value by its length alone, and the file it
changed stays encrypted and is committed as it is. It reads one line a value.

**A machine's file and a value of several lines.** A repository path that goes on into
`machines/<m>`, as `mise run secret monoflake/cloud/machines/<m> upgrade`, writes that machine's own
`secrets.json`, its names in lowercase and hyphens as sops-nix reads them, where a repository's are
in capitals. One that goes on into `platforms/<p>` writes the file a platform's machines share, as
the test platform's bucket read token, and one into `runner` writes the self-hosted runner's, both
named as a machine's are. `--from <file>` is given once, takes one name and the whole file as its
value, its lines and its final newline kept, handed to sops without passing through the shell; a
relative path is read from where the command was typed, and a file that is not UTF-8 text is
refused. It is for a value made by a program, as a key or an environment file, and is reported by
its size alone; a value of one line is typed, so no editor's newline joins it. A key a program
generates for it is made in a 0700 directory under the scratchpad and removed with `rm` once
entered, as ["An agent removes what it made with rm, and trashes what it did not"](deletion.md#an-agent-removes-what-it-made-with-rm-and-trashes-what-it-did-not) has it, and only
its public half is kept.

```
$ mise run secret platform BACKUP_S3_ENDPOINT BACKUP_S3_REGION
secret: /Users/canmi/workspace/repos/platform/secrets.json
  BACKUP_S3_ENDPOINT: ••••••••••••••••••••••••••••••••••••••
  BACKUP_S3_ENDPOINT set, 38 characters
  BACKUP_S3_REGION is set already; replace it? [y/N] y
  BACKUP_S3_REGION: ••••••••••••
  BACKUP_S3_REGION set, 12 characters
secret: 2 set in /Users/canmi/workspace/repos/platform/secrets.json,
  still encrypted; it is committed as it is
```

**A value the author holds, an agent asks for by this command, never for the value.** It names the
repository and the names, the author runs it in their own terminal, and the agent reads only that
the names now exist. A value pasted into a chat is in a transcript, and that is not undone.

**A secret no person holds, random bytes a program makes, the agent generates and enters itself**:
made in a 0700 directory under its scratchpad, entered by `--from`, never printed, and the file
removed with `rm`. The test platform's `salt-master`, the salt master of RFC b8f35, is one, entered
so on 2026-11-03 into monoflake/cloud's `platforms/test/secrets.json`.

### Three things that will bite

**JSON, not dotenv.** mise parses a `.env` as plain dotenv before looking for sops metadata and
fails on the age block. JSON puts that metadata under a `sops` key it recognizes.

**No empty placeholders.** sops leaves `""` untouched, and mise then rejects the whole file because
a value lacks the `ENC[` prefix. Write `"unset"` instead of `""`.

**The circular trap.** A broken `secrets.json` makes every task that loads it fail, and `mise exec`
too where a repository still loads it globally -- including for the sops you would use to repair it.
Call sops by absolute path when fixing it.

`mise run secrets` refuses any file `.sops.yaml` claims that is not actually encrypted, and runs
first in `verify` because it is the only check there guarding something irreversible: a plaintext
credential reaching the remote is not undone by deleting the file.
