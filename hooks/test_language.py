from __future__ import annotations

import json
import pathlib
import tempfile
import unittest

import language

ENGLISH = (
	"The sidebar divider can now be dragged, and its width is stored in localStorage under the "
	"reader record, so a reload keeps it."
)
CHINESE = "sidebar 分割线现在可以拖动了，宽度存进 localStorage 的 reader 记录，刷新后保持。"


def claude(role: str, text: str, **extra: object) -> dict:
	if role == "tool":
		return {"type": "user", "message": {"role": "user", "content": [{"type": "tool_result"}]}}
	content = text if role == "user" else [{"type": "text", "text": text}]
	return {"type": role, "message": {"role": role, "content": content}, **extra}


def codex(role: str, text: str) -> dict:
	kind = "output_text" if role == "assistant" else "input_text"
	return {
		"type": "response_item",
		"payload": {"type": "message", "role": role, "content": [{"type": kind, "text": text}]},
	}


class LanguageTest(unittest.TestCase):
	def decide(self, records: list[dict]) -> dict:
		with tempfile.TemporaryDirectory() as directory:
			path = pathlib.Path(directory) / "transcript.jsonl"
			path.write_text("\n".join(json.dumps(r) for r in records) + "\n", encoding="utf-8")
			return language.response({"hook_event_name": "Stop", "transcript_path": str(path)})

	def test_an_english_reply_to_a_chinese_message_is_held(self) -> None:
		result = self.decide([claude("user", "把分割线做成可以拖动"), claude("assistant", ENGLISH)])
		self.assertEqual(result["decision"], "block")
		self.assertIn("spec/voice.md", result["reason"])

	def test_a_chinese_reply_with_english_nouns_passes(self) -> None:
		self.assertEqual(self.decide([claude("user", "拖动分割线"), claude("assistant", CHINESE)]), {})

	def test_an_english_status_line_mid_turn_is_held_too(self) -> None:
		result = self.decide(
			[
				claude("user", "拖动分割线"),
				claude("assistant", ENGLISH),
				claude("tool", ""),
				claude("assistant", CHINESE),
			]
		)
		self.assertEqual(result["decision"], "block")

	def test_a_turn_that_was_held_is_judged_on_what_it_wrote_afterwards(self) -> None:
		feedback = claude("user", "Stop hook feedback:\nThis turn spoke to the user in English.")
		feedback["isMeta"] = True
		records = [claude("user", "拖动分割线"), claude("assistant", ENGLISH), feedback]
		self.assertEqual(self.decide([*records, claude("assistant", CHINESE)]), {})
		self.assertEqual(self.decide([*records, claude("assistant", ENGLISH)])["decision"], "block")

	def test_a_user_writing_english_is_answered_in_english(self) -> None:
		self.assertEqual(self.decide([claude("user", "Answer in English, please."), claude("assistant", ENGLISH)]), {})

	def test_injected_context_is_not_the_user_speaking(self) -> None:
		records = [
			claude("user", "拖动分割线"),
			claude("user", "<system-reminder>English context</system-reminder>"),
			claude("assistant", ENGLISH),
		]
		self.assertEqual(self.decide(records)["decision"], "block")

	def test_code_and_short_lines_are_not_prose(self) -> None:
		fenced = "```sh\n" + ENGLISH + "\n```"
		self.assertEqual(self.decide([claude("user", "给我命令"), claude("assistant", fenced)]), {})
		self.assertEqual(self.decide([claude("user", "路径？"), claude("assistant", "apps/cms/src/lib/sidebar.ts")]), {})

	def test_the_codex_transcript_is_read_the_same_way(self) -> None:
		held = self.decide([codex("user", "拖动分割线"), codex("assistant", ENGLISH)])
		self.assertEqual(held["decision"], "block")
		self.assertEqual(self.decide([codex("user", "拖动分割线"), codex("assistant", CHINESE)]), {})
		injected = [codex("user", "拖动分割线"), codex("user", "<environment_context>x</environment_context>")]
		self.assertEqual(self.decide([*injected, codex("assistant", ENGLISH)])["decision"], "block")

	def test_without_a_transcript_the_last_message_is_judged(self) -> None:
		payload = {"hook_event_name": "Stop", "last_assistant_message": ENGLISH}
		self.assertEqual(language.response(payload)["decision"], "block")
		payload["last_assistant_message"] = CHINESE
		self.assertEqual(language.response(payload), {})

	def test_a_missing_transcript_is_not_a_failure(self) -> None:
		self.assertEqual(language.response({"hook_event_name": "Stop", "transcript_path": "/nonexistent"}), {})


if __name__ == "__main__":
	unittest.main()
