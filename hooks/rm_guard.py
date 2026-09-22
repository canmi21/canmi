"""The rm an agent's shell finds first: a whitelist over the paths rm may unlink.

Every operand is judged after the shell has expanded it, which is the point -- `rm -rf "$DIR/"`
with an empty DIR arrives here as `/`, where no reading of the command text could have seen it.
A refusal deletes nothing at all, not the operands that would have passed.
See spec/toolchain.md, "rm is guarded, not banned".

Dependencies are limited to the standard library for the system Python required by
spec/toolchain.md.
"""

from __future__ import annotations

import os
import sys
from dataclasses import dataclass

sys.dont_write_bytecode = True

REAL_RM = "/bin/rm"
WORKSPACE = os.path.dirname(os.path.dirname(os.path.realpath(__file__)))

CACHES = (
	"Library/Caches",
	"Library/Developer/Xcode/DerivedData",
	"Library/pnpm/store",
	".cache",
	".npm",
	".bun/install/cache",
	".cargo/registry",
	".cargo/git",
)
USER_FILES = (
	"Desktop",
	"Documents",
	"Downloads",
	"Movies",
	"Music",
	"Pictures",
	"Public",
	"Library/Mobile Documents",
)
VCS_STORES = (".jj", ".git")


@dataclass(frozen=True)
class Places:
	home: str
	workspace: str
	allowed: tuple[str, ...]
	user_files: tuple[str, ...]


def places(env: dict[str, str], workspace: str = WORKSPACE) -> Places:
	home = os.path.realpath(env.get("HOME") or os.path.expanduser("~"))
	temp = {os.path.realpath("/tmp")}
	if env.get("TMPDIR"):
		temp.add(os.path.realpath(env["TMPDIR"]))
	return Places(
		home=home,
		workspace=workspace,
		allowed=(workspace, *sorted(temp), *(os.path.join(home, c) for c in CACHES)),
		user_files=tuple(os.path.join(home, d) for d in USER_FILES),
	)


def is_agent(env: dict[str, str]) -> bool:
	"""Claude Code sets CLAUDECODE and AI_AGENT; Codex is recognized by its CODEX_ prefix."""
	return bool(env.get("CLAUDECODE") or env.get("AI_AGENT")) or any(
		key.startswith("CODEX_") for key in env
	)


def operands(args: list[str]) -> list[str]:
	"""BSD rm's getopt: options end at `--` or at the first argument that is not one."""
	for i, arg in enumerate(args):
		if arg == "--":
			return args[i + 1 :]
		if not arg.startswith("-") or arg == "-":
			return args[i:]
	return []


def resolve(operand: str, cwd: str) -> str:
	"""Where rm would act: the link itself for a symlink, the target once a slash follows it."""
	path = os.path.join(cwd, operand)
	head, tail = os.path.split(path.rstrip("/"))
	if tail in ("", ".", "..") or operand.endswith("/"):
		return os.path.realpath(path)
	return os.path.join(os.path.realpath(head), tail)


def _same(a: str, b: str) -> bool:
	# APFS is case-insensitive by default, so ~/downloads is ~/Downloads.
	return a.casefold().rstrip("/") == b.casefold().rstrip("/")


def _within(path: str, root: str) -> bool:
	return _same(path, root) or path.casefold().startswith(root.casefold().rstrip("/") + "/")


def verdict(operand: str, path: str, where: Places) -> str | None:
	"""None when rm may go ahead, otherwise the reason it may not."""
	hard = "nothing deletes this; if the path came from a variable, the variable is wrong or empty"
	if operand == "":
		return "the operand is empty, which is almost always a variable that expanded to nothing"
	repos = os.path.join(where.workspace, "repos")
	if (
		_same(path, "/")
		or _same(path, "/Users")
		or _same(path, where.home)
		or _same(path, repos)
		or _same(os.path.dirname(path), repos)
		or any(_same(path, root) for root in where.allowed)
	):
		return hard
	if any(_within(path, d) for d in where.user_files):
		return f"this holds the user's own files; `trash {operand}` works here and is recoverable"
	if _within(path, "/Users") and not _within(path, where.home):
		return "this is another user's directory; " + hard
	if any(part.casefold() in VCS_STORES for part in path.split("/")):
		return "this is a version-control store; " + hard
	if any(_within(path, root) for root in where.allowed):
		return None
	return (
		"this is outside the directories rm may touch (the workspace, temp, caches); "
		f"use `trash {operand}` instead"
	)


def main(args: list[str], env: dict[str, str] | None = None, cwd: str | None = None) -> int:
	env = dict(os.environ) if env is None else env
	if not is_agent(env):
		os.execv(REAL_RM, ["rm", *args])
	where = places(env)
	cwd = cwd or os.getcwd()
	refused = [
		(operand, path, reason)
		for operand in operands(args)
		for path in [resolve(operand, cwd)]
		for reason in [verdict(operand, path, where)]
		if reason
	]
	for operand, path, reason in refused:
		print(f"rm: refused {operand!r} ({path}): {reason}", file=sys.stderr)
	if refused:
		print("rm: nothing was deleted", file=sys.stderr)
		return 1
	os.execv(REAL_RM, ["rm", *args])
	return 0  # unreachable


if __name__ == "__main__":
	sys.exit(main(sys.argv[1:]))
