import { mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { afterEach, beforeEach, describe, expect, test } from 'vitest';
import { blocks, columns, docstringSpans, prose, unlinked } from './comments.ts';
import { allowed, compare, major } from './outdated.ts';
import { unencrypted } from './secrets.ts';

describe('a secrets file', () => {
	test('is safe only as sops writes it, every value encrypted', () => {
		expect(unencrypted('{"sops": {}, "A": "ENC[x]"}')).toBeUndefined();
		expect(unencrypted('{"A": "plain"}')).toBe('no sops block: this is plaintext');
		expect(unencrypted('{"sops": {}, "B": "", "A": "plain"}')).toBe(
			'values are not encrypted: A, B',
		);
		expect(unencrypted('not json')).toMatch(/^not readable as JSON/);
	});
});

describe('a comment', () => {
	test('is measured with tabs at two, less its links, in characters', () => {
		expect(columns('\t// a')).toBe(6);
		expect(columns('// see https://example.com/a/very/long/path.')).toBe(8);
		expect(unlinked('// `https://kept` https://gone')).toBe('// `https://kept` ');
		expect(columns('// 渲染')).toBe(5);
	});

	test('says something when it carries text, a link alone saying nothing', () => {
		expect(prose('// words')).toBe(true);
		expect(prose(' * ')).toBe(false);
		expect(prose('// https://example.com')).toBe(false);
		expect(prose('// 中文 https://example.com')).toBe(true);
	});

	test('block opening a file is told from one after code, a directive leading neither, as the Python gate measured them', () => {
		const lines = [
			'#!/usr/bin/env node',
			'//MISE description="x"',
			'// one',
			'// two',
			'code();',
			'/**',
			' * three',
			' */',
		];
		expect(blocks(lines)).toEqual([
			[3, 2, 6, true],
			[6, 1, 8, false],
		]);
		expect(blocks(['// @generated', '// x'])).toEqual([]);
	});
});

describe("a Python file's docstrings", () => {
	let dir: string;
	beforeEach(() => {
		dir = mkdtempSync(join(tmpdir(), 'comments-'));
	});
	afterEach(() => rmSync(dir, { recursive: true, force: true }));

	test("are found by Python's parser: the module's opens the file, a function's does not", () => {
		const path = join(dir, 'a.py');
		const text = '"""The module,\nsaid twice."""\n\n\ndef f():\n\t"""A function."""\n\treturn 1\n';
		writeFileSync(path, text);
		const spans = docstringSpans([path]).get(path) ?? [];
		expect(spans.toSorted()).toEqual([
			[1, 2, true],
			[6, 6, false],
		]);
		expect(blocks(text.split('\n'), spans)).toEqual([
			[1, 2, 14, true],
			[6, 1, 19, false],
		]);
	});
});

describe('a version', () => {
	test('sorts by its numbers, a release above its prerelease', () => {
		expect(['1.10.0', '1.9.0', '1.10.0-rc.1'].toSorted(compare)).toEqual([
			'1.9.0',
			'1.10.0-rc.1',
			'1.10.0',
		]);
		expect(compare('2.0.0', '2.0.0')).toBe(0);
	});

	test('major is the part a caret range holds', () => {
		expect(major('4.13.12')).toBe('4');
		expect(major('0.28.2')).toBe('0.28');
		expect(major('0.0.3')).toBe('0.0.3');
	});

	test('allowed at two majors is what versions.toml says, with its reason', () => {
		const text =
			'[several]\n# why\n"@types/node" = "the \\"types\\" lag"\nvite = "two"\n[other]\nx = "y"\n';
		expect(allowed(text)).toEqual(
			new Map([
				['@types/node', 'the "types" lag'],
				['vite', 'two'],
			]),
		);
	});
});
