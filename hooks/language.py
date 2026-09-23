#!/usr/bin/env python3
"""Hold a turn open while what it said to the user is not in the language they are spoken to in.

spec/voice.md: the chat is simplified Chinese with English technical nouns left as they are. The
rule was written down, loaded at every start, and still broken twice in one session -- the reply
drifts into English after a stretch of reading English specs and English tool output, and the
drift is invisible from inside it. So it is checked where a turn ends rather than remembered.

What is checked is every block of prose the assistant wrote since the user last spoke, or since
this hook last held the turn -- so a turn that was held is judged on what it wrote afterwards, and
restating the reply in Chinese is what releases it. A block is English when, once code is taken
out, it has a sentence's worth of Latin letters and no Chinese at all; a short block, a path or a
command alone, is not prose and is left alone.

The user may ask for another language, and spec/voice.md lets them. The one form of that the
transcript can show is the user writing English themselves, so a turn answering an English message
is not checked.

Both harnesses are read: the payload's `last_assistant_message` where there is no transcript, and
either transcript format where there is. Dependencies are limited to the standard library, for the
reason given in spec/toolchain.md.
"""

from __future__ import annotations

import json
import re

CJK = re.compile(r"[㐀-䶿一-鿿豈-﫿]")
FENCED = re.compile(r"```.*?```", re.S)
INLINE = re.compile(r"`[^`\n]*`")
LATIN = re.compile(r"[A-Za-z]")
# Fewer letters than this is a word, a path or a command, not a reply written in a language.
PROSE_LETTERS = 60


def english(text: str) -> bool:
	"""Whether `text` is prose written in English rather than in Chinese."""
	prose = INLINE.sub("", FENCED.sub("", text))
	return len(LATIN.findall(prose)) >= PROSE_LETTERS and not CJK.search(prose)


def texts(content: object, kinds: tuple[str, ...]) -> list[str]:
	"""The text parts of a message's content, whichever shape the harness wrote it in."""
	if isinstance(content, str):
		return [content]
	if not isinstance(content, list):
		return []
	return [
		part["text"]
		for part in content
		if isinstance(part, dict) and part.get("type") in kinds and isinstance(part.get("text"), str)
	]


def entry(line: str) -> tuple[str, list[str], bool] | None:
	"""One transcript line as (role, texts, spoken by the user), or None when it is neither side's words.

	Claude Code writes `{"type": "user"|"assistant", "message": {...}}`, where a user entry is also
	how a tool's result and a hook's feedback arrive; Codex writes `{"type": "response_item",
	"payload": {"type": "message", "role": ..., "content": [...]}}`, where injected context arrives
	as a user message opening with a tag. Only the user's own words count as the user speaking.
	"""
	try:
		record = json.loads(line)
	except ValueError:
		return None
	if not isinstance(record, dict):
		return None

	if record.get("type") in ("user", "assistant"):
		message = record.get("message")
		if not isinstance(message, dict):
			return None
		content = message.get("content")
		if record["type"] == "assistant":
			return ("assistant", texts(content, ("text",)), False)
		parts = texts(content, ("text",))
		if not parts:
			return None  # a tool result, which is neither side speaking
		spoken = not record.get("isMeta") and not parts[0].lstrip().startswith("<")
		return ("user", parts, spoken)

	payload = record.get("payload")
	if record.get("type") == "response_item" and isinstance(payload, dict):
		if payload.get("type") != "message":
			return None
		role = payload.get("role")
		if role == "assistant":
			return ("assistant", texts(payload.get("content"), ("output_text",)), False)
		if role in ("user", "developer"):
			parts = texts(payload.get("content"), ("input_text",))
			spoken = role == "user" and bool(parts) and not parts[0].lstrip().startswith(("<", "#"))
			return ("user", parts, spoken)
	return None


def turn(transcript: str) -> tuple[str | None, list[str]]:
	"""What the user last said, and what the assistant has written since anything last spoke to it."""
	asked: str | None = None
	written: list[str] = []
	with open(transcript, encoding="utf-8") as source:
		for line in source:
			found = entry(line)
			if found is None:
				continue
			role, parts, spoken = found
			if role == "assistant":
				written.extend(parts)
				continue
			written = []
			if spoken:
				asked = "\n".join(parts)
	return asked, written


def response(payload: dict) -> dict:
	"""Return the continuation decision for one Stop payload, if any."""
	asked: str | None = None
	written: list[str] = []
	transcript = payload.get("transcript_path")
	try:
		if isinstance(transcript, str) and transcript:
			asked, written = turn(transcript)
	except OSError:
		pass
	if not written and isinstance(payload.get("last_assistant_message"), str):
		written = [payload["last_assistant_message"]]

	if asked is not None and not CJK.search(asked):
		return {}
	if not any(english(text) for text in written):
		return {}
	return {
		"decision": "block",
		"reason": (
			"This turn spoke to the user in English. spec/voice.md: the chat is simplified Chinese, "
			"with English technical nouns kept as they are; only file content is English. Restate "
			"what you told the user in Chinese -- the result, what is pending, what to check -- and "
			"then finish the turn."
		),
	}
