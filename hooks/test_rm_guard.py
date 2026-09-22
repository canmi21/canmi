from __future__ import annotations

import os
import pathlib
import subprocess
import tempfile
import unittest

import rm_guard

ROOT = pathlib.Path(__file__).resolve().parents[1]
SHIM = ROOT / "hooks" / "bin" / "rm"
HOME = "/Users/me"
WHERE = rm_guard.places({"HOME": HOME, "TMPDIR": "/tmp"}, workspace="/Users/me/workspace")


def judge(operand: str, cwd: str = "/Users/me/workspace") -> str | None:
	return rm_guard.verdict(operand, rm_guard.resolve(operand, cwd), WHERE)


class VerdictTest(unittest.TestCase):
	def test_inside_the_whitelist_passes(self) -> None:
		for operand in (
			"dist",
			"repos/lattice/target",
			"/Users/me/workspace/node_modules/.cache",
			"/tmp/claude-501/scratch/out.json",
			"/Users/me/Library/Caches/mise",
			"/Users/me/.cargo/registry/cache",
		):
			with self.subTest(operand=operand):
				self.assertIsNone(judge(operand))

	def test_an_empty_variable_is_refused_in_every_spelling(self) -> None:
		for operand in ("", "/", "/.", "//", "..", "../..", "/Users", "/Users/me", "/Users/me/"):
			with self.subTest(operand=operand):
				self.assertIsNotNone(judge(operand))

	def test_the_roots_themselves_are_refused(self) -> None:
		for operand in (
			"/Users/me/workspace",
			".",
			"repos",
			"repos/lattice",
			"/Users/me/Library/Caches",
			"/tmp",
			".jj",
			"repos/lattice/.jj/repo",
		):
			with self.subTest(operand=operand):
				self.assertIsNotNone(judge(operand))

	def test_user_files_point_at_trash(self) -> None:
		for operand in ("/Users/me/Downloads/a.dmg", "/Users/me/downloads/a.dmg", "/Users/me/Documents"):
			with self.subTest(operand=operand):
				self.assertIn("trash", judge(operand) or "")

	def test_everything_else_is_outside(self) -> None:
		self.assertIn("outside", judge("/Users/me/.config/fish/config.fish") or "")
		self.assertIn("outside", judge("/opt/homebrew/bin/x") or "")
		self.assertIn("another user", judge("/Users/other/x") or "")

	def test_options_stop_where_getopt_stops(self) -> None:
		self.assertEqual(rm_guard.operands(["-rf", "a", "-v"]), ["a", "-v"])
		self.assertEqual(rm_guard.operands(["-f", "--", "-x"]), ["-x"])
		self.assertEqual(rm_guard.operands(["-rf"]), [])


class ShimTest(unittest.TestCase):
	def run_shim(self, *args: str, agent: bool = True) -> subprocess.CompletedProcess:
		env = {k: v for k, v in os.environ.items() if not rm_guard.is_agent({k: v})}
		if agent:
			env["CLAUDECODE"] = "1"
		return subprocess.run(
			[str(SHIM), *args], capture_output=True, text=True, env=env, check=False
		)

	def test_a_refusal_deletes_none_of_the_operands(self) -> None:
		with tempfile.TemporaryDirectory() as scratch:
			kept = pathlib.Path(scratch, "kept")
			kept.write_text("x")
			result = self.run_shim("-f", str(kept), "")
			self.assertEqual(result.returncode, 1)
			self.assertIn("nothing was deleted", result.stderr)
			self.assertTrue(kept.exists())

	def test_an_allowed_operand_is_deleted_by_the_real_rm(self) -> None:
		with tempfile.TemporaryDirectory() as scratch:
			gone = pathlib.Path(scratch, "gone")
			gone.mkdir()
			result = self.run_shim("-r", str(gone))
			self.assertEqual(result.returncode, 0, result.stderr)
			self.assertFalse(gone.exists())

	def test_outside_an_agent_the_shim_is_the_real_rm(self) -> None:
		result = self.run_shim("-f", "", agent=False)
		self.assertNotIn("refused", result.stderr)
