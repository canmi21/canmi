"""The reference rules two gates share: a link resolves, a citation resolves, a section exists.

Both `refs` tasks -- this repository's and lattice's -- run those three over different trees, so
they live here once and each task states only what is its own: which files it reads, how a
citation resolves from where it sits, and whatever else it checks. A project reaches this file by
position, the way it already reaches `.editorconfig` and the `[tools]` pins -- see
spec/architecture/repos.md, "Configuration is inherited by position, not copied".

A library, not a task: no entry point and no `#MISE` header, so mise never offers it as a third
gate and the two that exist stay two, each printing its own count.
"""

from __future__ import annotations

import pathlib
import re
import subprocess
from collections.abc import Callable, Collection, Iterable

MD_LINK = re.compile(r"\[[^\]]*\]\(([^)]+)\)")
# A path as a doc writes one, lowercase throughout, which is what spec/naming.md asks of a name
# this author's trees carry.
DOC_PATH = r"[a-z0-9-]+(?:/[a-z0-9-]+)*\.md"
# The tail of a citation that already carries its prefix. Only the basename widens, for the names
# a framework fixes; directories stay lowercase, which is spec/naming.md restated rather than a
# convenience. Kept apart from DOC_PATH, which feeds DOC_ANCHOR and has no prefix to hold it down:
# widening it there reads an uppercase word before `.md` anywhere in prose as a target.
DOC_TAIL = r"(?:[a-z0-9-]+/)*[A-Za-z0-9-]+\.md"
# The entry point every tree carries at its root, under both names agents read it by. Citable by
# anchor and by nothing else, and the list stops here: `README.md` and `VENDOR.md` are
# per-directory names, so a bare one resolves to whichever the walk reaches and a check that
# follows the wrong file is worse than no check. A pathed one is what DOC_TAIL already covers.
ROOT_DOCS = r"AGENTS\.md"
# A citation may name a section: `spec/<f>.md, "Name"` or `spec/<f>.md ("Name")`. The quote need
# not sit against it, but it may not cross a full stop or a semicolon, or a sentence quoting
# something else is read as this one's anchor. One character at least has to separate the two: a
# path written as a value in a list is followed by its own closing quote, which would otherwise
# open an anchor that runs to the next quote in the file.
ANCHOR = r'[^".;\n]{1,60}?"(?P<anchor>[^"]{6,160})"'
# A doc cites by markdown link or by bare path, and either may be relative to the citing file.
DOC_ANCHOR = re.compile(rf"(?:\[[^\]]*\]\()?(?P<target>(?:\.\./)*{DOC_PATH})\)?{ANCHOR}")
# An anchor may wrap, so continuation lines fold away before matching. `///` and `//!` come before
# `//`: the shorter alternative matches first and leaves a stray slash inside the quote, which
# reads as a break in an anchor that is intact. `#` is here for `.gitignore` and `.gitattributes`,
# whose anchors wrap across it exactly as a docstring's do.
COMMENT_WRAP = re.compile(r"\n[ \t]*(?:\*|///|//!|//|#)?[ \t]*")
# Prose carries no comment markers, and a `*` opening a line is emphasis rather than one.
PROSE_WRAP = re.compile(r"\n\s*")
SPACES = re.compile(r"\s+")
NOT_WORD = re.compile(r"[^a-z0-9 ]")
FENCE = re.compile(r"```.*?```", re.S)
INLINE_CODE = re.compile(r"`[^`\n]+`")

BODIES: dict[pathlib.Path, str] = {}


def read(path: pathlib.Path) -> str:
	try:
		return path.read_text()
	except (OSError, UnicodeDecodeError):
		return ""


def tracked(
	root: pathlib.Path,
	skip_files: Collection[str] = (),
	skip_dirs: Collection[str] = (),
) -> list[pathlib.Path]:
	"""Every file git knows about under `root`, less the names and the trees the caller excludes.

	The candidate set comes from git because `.gitignore` is already the one home of "this is not
	ours"; a second list can only drift from the first. It is also what keeps a nested repository
	out: the one above ignores it, and it carries a gate of its own.
	"""
	listing = subprocess.run(
		["git", "-C", str(root), "ls-files", "--cached", "--others", "--exclude-standard", "-z"],
		capture_output=True,
		text=True,
		check=True,
	)
	skipped = set(skip_dirs)
	return [
		path
		for name in listing.stdout.split("\0")
		if name
		for path in [root / name]
		if path.name not in skip_files and not skipped & set(pathlib.PurePath(name).parts)
	]


def extensionless_text(path: pathlib.Path) -> bool:
	"""Whether a tracked file with no extension is text, and so can hold a citation.

	A shebang is the obvious tell and it is not enough: it finds the task scripts and misses
	`.gitignore` and `.gitattributes`, which cite without being executable. Decoding to text with
	no NUL in it covers both, and all it lets in besides costs a scan and nothing else.
	"""
	if path.suffix:
		return False
	body = read(path)
	return bool(body) and "\0" not in body


def citing_files(files: Iterable[pathlib.Path], suffixes: Collection[str]) -> list[pathlib.Path]:
	"""Code, plus the extensionless text lying beside it.

	A suffix allowlist is blind to precisely the files a checker lives among, which is how nine
	citations of a spec file that never existed survived in lattice's. In any of these a
	path-shaped citation is a citation wherever it sits -- comment, docstring or printed message
	alike, since a dead citation shown to whoever fails a check is still dead.
	"""
	return [path for path in files if path.suffix in suffixes or extensionless_text(path)]


def without_code(text: str) -> str:
	"""Blank out fenced blocks and inline code, keeping line structure intact.

	A doc describing how a citation is spelled writes one inside backticks. That is an example of
	a link, not a link, and reading it as a target makes the rules unable to state themselves.
	"""
	text = FENCE.sub(lambda m: "\n" * m.group(0).count("\n"), text)
	return INLINE_CODE.sub(lambda m: " " * len(m.group(0)), text)


def flatten(text: str) -> str:
	"""Text reduced to its lowercase words, every other character becoming a space.

	Applied to the heading's file and to the anchor alike, so a heading spelling a name in
	backticks or separating a clause with an em dash still matches the citation quoting it.
	Collapse last, not first: dropping `` `spec/` `` leaves three spaces where the citation's
	`spec/` leaves two, and a squeeze done beforehand never sees either.
	"""
	return SPACES.sub(" ", NOT_WORD.sub(" ", text.lower())).strip()


def flattened(path: pathlib.Path | None) -> str | None:
	"""One file flattened and kept, or None when it is not there."""
	if path is None or not path.is_file():
		return None
	if path not in BODIES:
		BODIES[path] = flatten(read(path))
	return BODIES[path]


def code_anchor(target: str) -> re.Pattern[str]:
	"""The anchor pattern for one gate's idea of a citation, which is the half that differs.

	A gate says what a citation looks like to it -- this repository's reaches into `repos/`, a
	project's does not -- and the quoting rule beside it is the same either way.
	"""
	return re.compile(rf"(?P<target>{target}){ANCHOR}")


def pair_graph(
	root: pathlib.Path,
	files: Iterable[pathlib.Path],
	pattern: re.Pattern[str],
) -> dict[str, list[str]]:
	"""cited doc -> the files that cite it."""
	graph: dict[str, list[str]] = {}
	for path in files:
		rel = str(path.relative_to(root))
		for cited in sorted(set(pattern.findall(read(path)))):
			graph.setdefault(cited, []).append(rel)
	return graph


def dead_links(
	root: pathlib.Path,
	docs: Iterable[pathlib.Path],
	elsewhere: Callable[[pathlib.Path], bool] | None = None,
) -> tuple[list[str], list[str]]:
	"""Markdown links that point at nothing, split from those the caller reads as absent instead.

	`elsewhere` decides that split: one gate calls a link into a project nobody has cloned here a
	note rather than a failure, and a gate with nothing below it passes none and gets an empty
	second list.
	"""
	dead: list[str] = []
	absent: list[str] = []
	for doc in docs:
		for match in MD_LINK.finditer(without_code(read(doc))):
			target = match.group(1)
			if target.startswith(("http://", "https://", "#", "mailto:")):
				continue
			landing = doc.parent / target.split("#")[0]
			if landing.exists():
				continue
			entry = f"{doc.relative_to(root)} -> {target}"
			(absent if elsewhere and elsewhere(landing) else dead).append(entry)
	return dead, absent


def dead_anchors(
	root: pathlib.Path,
	sources: Iterable[tuple[pathlib.Path, re.Pattern[str], re.Pattern[str]]],
	resolve: Callable[[pathlib.Path, str], pathlib.Path | None],
) -> tuple[list[str], int]:
	"""Section names quoted from code or from another doc that the named file no longer holds.

	A file existing does not mean the section named inside it still does, so a heading is part of
	the interface. Read raw rather than through `without_code`: an anchor quotes its heading
	verbatim, inline code and all. A target that is not there is the citation check's to report.
	"""
	dead: list[str] = []
	seen = 0
	for path, pattern, wrap in sources:
		for match in pattern.finditer(wrap.sub(" ", read(path))):
			cited = match.group("target")
			body = flattened(resolve(path, cited))
			if body is None:
				continue
			seen += 1
			if flatten(match.group("anchor")) not in body:
				dead.append(f'{path.relative_to(root)} -> {cited} ("{match.group("anchor")}")')
	return dead, seen
