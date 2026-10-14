/**
 * The gate holding every comment block in a repository to the limits in spec/code.md: at most six
 * body lines, ten for the block opening a file, and 100 columns with tabs at two -- the width oxfmt
 * and rustfmt give code, which neither rewraps. A body line is one carrying text: `/**`, `*\/`, a
 * blank `*`, a docstring's quotes and a link are punctuation. Paths given are measured instead of
 * the tree. A Python file's docstrings are found by Python's own parser, asked once for them all.
 */
import { execFileSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import { isAbsolute, join, relative } from 'node:path';

const WIDTH = 100;
const BODY = 6;
const OPENING = 10;
/** A fenced block in a document illustrates code rather than being it, so prose files are skipped. */
const SKIPPED = ['.md'];
/**
 * Opening a block, in the order they have to be tried: `///` before `//`. `#` is a comment only
 * when a space or the line end follows it -- `#[derive]`, `#id {` and `#fff` are code.
 */
const OPENERS = ['///', '//!', '//', '/**', '/*', '*/', '<!--', '"""', "'''", '#'];
const CLOSERS = ['*/', '-->', '"""', "'''"];
/** Read by a tool rather than a person: a shebang and mise's task header lead and are not prose. */
const DIRECTIVES = ['#!', '#MISE', '#USAGE', '//MISE'];
const PREAMBLE = ['set -'];
/**
 * A link, as spec/code.md's "A link is not length" means it: the two schemes a reader opens, the
 * run stopping before sentence punctuation.
 */
const LINK = /https?:\/\/(?:[^\s`'"]*[^\s`'".,;:!?)\]}])?/g;
/** A letter or a digit, in any script. What a link leaves behind is punctuation. */
const PROSE = /[\p{L}\p{N}]/u;

const startsWithAny = (text: string, prefixes: readonly string[]) =>
	prefixes.some((prefix) => text.startsWith(prefix));

/** The line with every link taken off it; one inside a backtick span is a token, and stays. */
export function unlinked(line: string): string {
	return line.replace(LINK, (match, offset: number) =>
		(line.slice(0, offset).split('`').length - 1) % 2 ? match : '',
	);
}

/** `line` with its tabs expanded to the next stop at two, as Python's `expandtabs(2)` does. */
function expanded(line: string): string {
	let out = '';
	for (const character of line) {
		if (character === '\t') out += ' '.repeat(2 - ([...out].length % 2));
		else if (character === '\n' || character === '\r') out = '';
		else out += character;
	}
	return out;
}

/** The width oxfmt and rustfmt would count, which is tabs at two, less any link. */
export function columns(line: string): number {
	return [...expanded(unlinked(line))].length;
}

/** What one comment line says, with its markers taken off. */
function textOf(line: string): string {
	let stripped = line.trim();
	const opener = OPENERS.find((one) => stripped.startsWith(one));
	if (opener) stripped = stripped.slice(opener.length);
	for (const closer of CLOSERS) {
		if (stripped.endsWith(closer)) stripped = stripped.slice(0, -closer.length);
	}
	return stripped.replace(/^\*+/, '').trim();
}

/** Whether a comment line says something; only one a link came off is judged by what is left. */
export function prose(line: string): boolean {
	const bare = unlinked(line);
	if (bare === line) return Boolean(textOf(line));
	return PROSE.test(textOf(bare));
}

/** Whether a stripped line opens or continues a `#` comment rather than naming something. */
function hashed(bare: string): boolean {
	return (
		(bare === '#' || bare.startsWith('# ') || bare.startsWith('#\t')) &&
		!startsWithAny(bare, DIRECTIVES)
	);
}

/** Whether a tool wrote this file, `@generated` in its first five lines: nobody's to fix. */
const generated = (lines: readonly string[]) =>
	lines.slice(0, 5).some((line) => line.includes('@generated'));

/** A block: its first line, its body lines, its widest column, and whether it opens the file. */
export type Block = [line: number, body: number, widest: number, opening: boolean];

/** A docstring's span, `[first, last, opensTheModule]`, from Python's own parser. */
type Span = [number, number, boolean];

const DOCSTRINGS = `
import ast, json, sys
spans = {}
for path in json.load(sys.stdin):
	try:
		tree = ast.parse(open(path, encoding="utf-8").read())
	except (OSError, SyntaxError, ValueError, UnicodeDecodeError):
		continue
	found = []
	for node in ast.walk(tree):
		if not isinstance(node, (ast.Module, ast.AsyncFunctionDef, ast.FunctionDef, ast.ClassDef)):
			continue
		first = node.body[0] if node.body else None
		if not isinstance(first, ast.Expr) or not isinstance(first.value, ast.Constant):
			continue
		if not isinstance(first.value.value, str) or first.end_lineno is None:
			continue
		found.append([first.lineno, first.end_lineno, isinstance(node, ast.Module)])
	spans[path] = found
print(json.dumps(spans))
`;

/** Each Python file's docstring spans, asked of python3 once for every file. */
export function docstringSpans(paths: readonly string[]): Map<string, Span[]> {
	if (!paths.length) return new Map();
	const answer = execFileSync('python3', ['-c', DOCSTRINGS], {
		input: JSON.stringify(paths),
		encoding: 'utf8',
		maxBuffer: 64 * 1024 * 1024,
	});
	return new Map(Object.entries(JSON.parse(answer) as Record<string, Span[]>));
}

/** A file's lines, or none where it cannot be read as UTF-8, as a decoder cannot read a binary. */
export function linesOf(path: string): string[] | undefined {
	try {
		// Newlines read as Python's text mode reads them, a byte-order mark kept as a character.
		const text = new TextDecoder('utf-8', { fatal: true, ignoreBOM: true }).decode(
			readFileSync(path),
		);
		return text.replace(/\r\n?/g, '\n').split('\n');
	} catch {
		return undefined;
	}
}

/** Whether a file is Python, by its suffix or its first line. */
export const isPython = (path: string, lines: readonly string[]) =>
	path.endsWith('.py') || (lines[0] ?? '').includes('python');

/** Every comment block in a file's `lines`, Python's docstrings given as `spans`. */
export function blocks(lines: readonly string[], spans: readonly Span[] = []): Block[] {
	if (generated(lines)) return [];
	const found: Block[] = [];
	const claimed = new Set<number>();
	for (const [first, last, module] of spans) {
		const body = lines.slice(first - 1, last);
		for (let number = first; number <= last; number++) claimed.add(number);
		const count = body.filter(prose).length;
		const widest = Math.max(...body.map(columns));
		found.push([first, count, widest, module]);
	}
	let codeSeen = false;
	let index = 0;
	while (index < lines.length) {
		const start = index;
		const bare = (lines[index] as string).trim();
		if (startsWithAny(bare, DIRECTIVES) || (!codeSeen && startsWithAny(bare, PREAMBLE))) {
			index += 1;
			continue;
		}
		if (claimed.has(index + 1)) {
			codeSeen = true;
			index += 1;
			continue;
		}
		let body: string[];
		if (bare.startsWith('/*') || bare.startsWith('<!--')) {
			const closer = bare.startsWith('/*') ? '*/' : '-->';
			while (index < lines.length && !(lines[index] as string).includes(closer)) index += 1;
			index = Math.min(index, lines.length - 1);
			body = lines.slice(start, index + 1);
			index += 1;
		} else if (bare.startsWith('//')) {
			while (index < lines.length && (lines[index] as string).trim().startsWith('//')) index += 1;
			body = lines.slice(start, index);
		} else if (hashed(bare)) {
			while (index < lines.length && hashed((lines[index] as string).trim())) index += 1;
			body = lines.slice(start, index);
		} else {
			codeSeen ||= Boolean(bare);
			index += 1;
			continue;
		}
		found.push([start + 1, body.filter(prose).length, Math.max(...body.map(columns)), !codeSeen]);
	}
	return found.toSorted(
		(a, b) => a[0] - b[0] || a[1] - b[1] || a[2] - b[2] || Number(a[3]) - Number(b[3]),
	);
}

/** The files to measure: everything version control lists, untracked but unignored among them. */
function files(root: string, given: readonly string[]): string[] {
	if (given.length) return [...given];
	const listing = execFileSync(
		'git',
		['-C', root, 'ls-files', '--cached', '--others', '--exclude-standard', '-z'],
		{ encoding: 'utf8', maxBuffer: 256 * 1024 * 1024 },
	);
	return listing
		.split('\0')
		.filter((name) => name && !SKIPPED.some((suffix) => name.endsWith(suffix)))
		.map((name) => join(root, name));
}

/** The gate: every block inside its limits, or each that is not, by where and by how much. */
export function main(root = process.cwd(), given: readonly string[] = process.argv.slice(2)): void {
	const read = files(root, given).map((path) => ({ path, lines: linesOf(path) }));
	const python = read
		.filter(({ path, lines }) => lines && isPython(path, lines))
		.map(({ path }) => path);
	const spans = docstringSpans(python);
	const over: string[] = [];
	let counted = 0;
	for (const { path, lines } of read) {
		if (!lines) continue;
		const inside = !isAbsolute(path) || !relative(root, path).startsWith('..');
		const name = inside && isAbsolute(path) ? relative(root, path) : path;
		for (const [line, body, widest, opening] of blocks(lines, spans.get(path) ?? [])) {
			counted += 1;
			const limit = opening ? OPENING : BODY;
			const why: string[] = [];
			if (widest > WIDTH) why.push(`${widest} columns over ${WIDTH}`);
			if (body > limit) why.push(`${body} body lines over ${limit}`);
			if (why.length) over.push(`${name}:${line}  ${why.join(', ')}`);
		}
	}
	if (over.length) {
		console.error('Comment blocks over a limit:\n');
		for (const problem of over) console.error(`  ${problem}`);
		console.error(
			'\nCut to the line that carries the point. A fact a second file would need is a rule and ' +
				'belongs in spec/; one only this file needs stays here, in fewer words. See spec/code.md, ' +
				'"How long, and where the rest of it goes".',
		);
		process.exit(1);
	}
	console.log(
		`comments OK: ${counted} blocks inside ${BODY}/${OPENING} body lines and ${WIDTH} columns`,
	);
}

if (import.meta.main) main();
