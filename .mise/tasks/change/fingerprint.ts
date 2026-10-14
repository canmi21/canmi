/**
 * What a file is to a build: two revisions of it compare equal here when no image built from them
 * could tell them apart. Rust source is its tokens, without comments or layout; a Dockerfile, a
 * `.dockerignore` and the image task are their lines without comments or blank ones; a declaration
 * or a crate's manifest is its parsed value. Anything else is its bytes. Read by ./deployable.ts.
 */
import { isDeepStrictEqual } from 'node:util';
import { parse } from 'smol-toml';

/** Where a crate keeps what `cargo build` never compiles into its binary. */
const UNBUILT_DIRECTORIES = new Set(['tests', 'benches', 'examples']);

/** A Dockerfile's parser directives, which look like comments and change the build. */
const DIRECTIVE = /^#\s*(syntax|check|escape)\s*=/i;

/** A heredoc's opening, `<<EOF`, `<<-EOF` or with the word quoted. */
const HEREDOC = /<<(-?)\s*["']?([A-Za-z_][A-Za-z0-9_]*)["']?/;

/** What starts a raw string, and a raw identifier, at the start of a token. */
const RAW_STRING = /(?:br|cr|r)(#*)"/y;
const RAW_IDENTIFIER = /r#[A-Za-z_][A-Za-z0-9_]*/y;

/** A character that may continue an identifier, a keyword or a number. */
const WORD = /[A-Za-z0-9_]/;

const OPENING = new Set(['(', '[', '{']);
const CLOSING = new Set([')', ']', '}']);

/** Words after which `(` opens a tuple, not a call's arguments. */
const KEYWORDS = new Set([
	'return',
	'in',
	'match',
	'if',
	'while',
	'break',
	'else',
	'let',
	'for',
	'move',
	'yield',
]);

const word = (character: string | undefined) => character !== undefined && WORD.test(character);

/**
 * Whether `path` goes into no image at all: prose, a license, or what a crate builds only for its
 * tests, benchmarks and examples.
 */
export function ignored(path: string, crateDirectories: Iterable<string> = []): boolean {
	const name = path.slice(path.lastIndexOf('/') + 1);
	if (name.endsWith('.md') || name.startsWith('LICENSE')) return true;
	for (const directory of crateDirectories) {
		const rest = path.startsWith(`${directory}/`) ? path.slice(directory.length + 1) : '';
		if (rest.includes('/') && UNBUILT_DIRECTORIES.has(rest.split('/', 1)[0] as string)) {
			return true;
		}
	}
	return false;
}

/** `pattern`, sticky, matched at `at` in `text`. */
function matchAt(pattern: RegExp, text: string, at: number): RegExpExecArray | null {
	pattern.lastIndex = at;
	return pattern.exec(text);
}

/**
 * The tokens of Rust source `text`, comments and whitespace dropped. A literal is kept whole, so a
 * change inside a string is a change; punctuation is one character a token, so `&&` and `& &`,
 * which rustfmt rewrites one into the other, are the same; and the commas rustfmt adds and removes
 * as it wraps a line are dropped, see `withoutOptionalCommas`.
 */
export function rustTokens(text: string): string[] {
	const tokens: string[] = [];
	const n = text.length;
	let i = 0;
	while (i < n) {
		const c = text[i] as string;
		let raw: RegExpExecArray | null;
		if (/\s/.test(c)) {
			i += 1;
		} else if (text.startsWith('//', i)) {
			const end = text.indexOf('\n', i);
			i = end < 0 ? n : end;
		} else if (text.startsWith('/*', i)) {
			let depth = 1;
			i += 2;
			while (i < n && depth) {
				if (text.startsWith('/*', i)) {
					depth += 1;
					i += 2;
				} else if (text.startsWith('*/', i)) {
					depth -= 1;
					i += 2;
				} else {
					i += 1;
				}
			}
		} else if ((raw = matchAt(RAW_STRING, text, i))) {
			const close = `"${raw[1]}`;
			const found = text.indexOf(close, i + raw[0].length);
			const end = found < 0 ? n : found + close.length;
			tokens.push(text.slice(i, end));
			i = end;
		} else if (c === '"' || ('bc'.includes(c) && text.startsWith('"', i + 1))) {
			const start = i;
			i += c === '"' ? 1 : 2;
			while (i < n && text[i] !== '"') i += text[i] === '\\' ? 2 : 1;
			i += 1;
			tokens.push(text.slice(start, i));
		} else if (c === "'" || (c === 'b' && text.startsWith("'", i + 1))) {
			const start = i;
			i += c === "'" ? 1 : 2;
			if (text.startsWith('\\', i) || text.startsWith("'", i + 1)) {
				// A character: an escape, or one character and its closing quote.
				while (i < n && text[i] !== "'") i += text[i] === '\\' ? 2 : 1;
				i += 1;
			} else {
				// A lifetime or a label: the quote and the name after it.
				while (i < n && word(text[i])) i += 1;
			}
			tokens.push(text.slice(start, i));
		} else if ((raw = matchAt(RAW_IDENTIFIER, text, i))) {
			tokens.push(raw[0]);
			i += raw[0].length;
		} else if (word(c)) {
			const start = i;
			while (i < n && word(text[i])) i += 1;
			tokens.push(text.slice(start, i));
		} else {
			tokens.push(c);
			i += 1;
		}
	}
	return withoutOptionalCommas(unbraced(withoutOptionalSemicolons(tokens)));
}

/** The index of the bracket closing the one at `index`, or the end. */
function closing(tokens: readonly string[], index: number): number {
	let depth = 0;
	for (let at = index; at < tokens.length; at++) {
		if (OPENING.has(tokens[at] as string)) depth += 1;
		else if (CLOSING.has(tokens[at] as string)) {
			depth -= 1;
			if (depth === 0) return at;
		}
	}
	return tokens.length;
}

const startsWith = (tokens: readonly string[], at: number, run: readonly string[]) =>
	run.every((token, offset) => tokens[at + offset] === token);

/**
 * `tokens` with the body of every match arm and closure that is a block of one expression written
 * without its braces, `=> { x }` as `=> x,` and `|y| { x }` as `|y| x`, as rustfmt writes it once
 * it fits on a line.
 */
function unbraced(input: readonly string[]): string[] {
	const tokens = [...input];
	let at = 0;
	while (at + 1 < tokens.length) {
		const arm = startsWith(tokens, at, ['=', '>', '{']);
		if (!arm && !startsWith(tokens, at, ['|', '{'])) {
			at += 1;
			continue;
		}
		const brace = arm ? at + 2 : at + 1;
		const end = closing(tokens, brace);
		const inner = tokens.slice(brace + 1, end);
		let depth = 0;
		let statement = false;
		for (const token of inner) {
			depth += Number(OPENING.has(token)) - Number(CLOSING.has(token));
			statement ||= depth === 0 && token === ';';
		}
		if (inner.length && !statement && end < tokens.length) {
			const comma = arm && tokens[end + 1] !== ',' ? [','] : [];
			tokens.splice(brace, end + 1 - brace, ...inner, ...comma);
		}
		at = brace;
	}
	return tokens;
}

/**
 * `tokens` without the `;` after a `return`, `break` or `continue` that ends a block, which
 * rustfmt adds when it puts the block on lines of its own and which changes nothing there.
 */
function withoutOptionalSemicolons(tokens: readonly string[]): string[] {
	const kept: string[] = [];
	const starts: (number | null)[] = [];
	tokens.forEach((token, index) => {
		const after = tokens[index + 1] ?? '';
		const start = starts.at(-1);
		if (token === ';' && starts.length && start !== null && start !== undefined) {
			if (after === '}' && ['return', 'break', 'continue'].includes(kept[start] as string)) return;
			kept.push(token);
			starts[starts.length - 1] = kept.length;
			return;
		}
		kept.push(token);
		// A statement begins only in a block.
		if (OPENING.has(token)) starts.push(token === '{' ? kept.length : null);
		else if (CLOSING.has(token) && starts.length) starts.pop();
	});
	return kept;
}

/**
 * `tokens` without the commas that mean nothing: one ending a list, right before `)`, `]`, `}` or
 * `>`, and one right after a block's `}` with more to follow, as after a match arm. The comma
 * ending a tuple's parentheses with no other is kept, since it makes `(x,)` a tuple; parentheses
 * after a name, `!`, `)`, `]` or `>` are a call's, whose last comma means nothing.
 */
function withoutOptionalCommas(tokens: readonly string[]): string[] {
	// Each open bracket: its commas so far, and whether it holds a call's arguments.
	const kept: string[] = [];
	const brackets: [number, boolean][] = [];
	tokens.forEach((token, index) => {
		const before = index ? (tokens[index - 1] as string) : '';
		const after = tokens[index + 1] ?? '';
		if (token === ',') {
			const top = brackets.at(-1);
			if (top) top[0] += 1;
			if (before === '}' && ![...CLOSING, '>'].includes(after)) return;
		} else if ((CLOSING.has(token) || token === '>') && kept.at(-1) === ',') {
			const top = brackets.at(-1);
			const tupleOfOne = token === ')' && top !== undefined && top[0] === 1 && !top[1];
			if (!tupleOfOne) kept.pop();
		}
		if (OPENING.has(token)) {
			const named = word(before[0]) && !KEYWORDS.has(before) && !/^[0-9]/.test(before);
			brackets.push([0, named || ['!', ')', ']', '>'].includes(before)]);
		} else if (CLOSING.has(token) && brackets.length) {
			brackets.pop();
		}
		kept.push(token);
	});
	return kept;
}

/** `text` split into lines as Python's `splitlines` does for these files: no empty last line. */
function lines(text: string): string[] {
	const split = text.split(/\r\n|\r|\n/);
	if (split.at(-1) === '') split.pop();
	return split;
}

/**
 * A Dockerfile's lines without its comments and blank lines, as Docker's own parser drops them; a
 * parser directive is kept, and so is every line of a heredoc, which Docker reads as written.
 */
export function dockerfileLines(text: string): string[] {
	const kept: string[] = [];
	let until: string | undefined;
	let dashed = false;
	for (const line of lines(text)) {
		if (until !== undefined) {
			kept.push(line);
			if ((dashed ? line.replace(/^\t+/, '') : line) === until) until = undefined;
			continue;
		}
		const stripped = line.trim();
		if (!stripped || (stripped.startsWith('#') && !DIRECTIVE.test(stripped))) continue;
		kept.push(line.trimEnd());
		const opened = HEREDOC.exec(line);
		if (opened) {
			dashed = opened[1] === '-';
			until = opened[2];
		}
	}
	return kept;
}

/**
 * A script's or an ignore file's lines without the blank ones and those that are only a comment;
 * a first line that is a shebang is kept.
 */
export function shellLines(text: string): string[] {
	const all = lines(text);
	const head = all[0]?.startsWith('#!') ? [all[0]] : [];
	const rest = all.slice(head.length).map((line) => line.trimEnd());
	return [...head, ...rest.filter((line) => line.trim() && !line.trim().startsWith('#'))];
}

/** A TOML file's value, or its text where it does not parse. */
export function tomlValue(text: string): unknown {
	try {
		return parse(text);
	} catch {
		return text;
	}
}

/** How `path` is read for a build, by its kind; undefined for its bytes. */
function normalizer(path: string): ((text: string) => unknown) | undefined {
	const name = path.slice(path.lastIndexOf('/') + 1);
	if (name.endsWith('.rs')) return rustTokens;
	if (name === 'Dockerfile' || name.endsWith('.Dockerfile')) return dockerfileLines;
	if (name === 'service.toml' || name === 'Cargo.toml') return tomlValue;
	if (name === '.dockerignore' || path === '.mise/tasks/image') return shellLines;
	return undefined;
}

/** Whether `path` is read as more than its bytes, and so is worth reading at all. */
export function normalized(path: string): boolean {
	return normalizer(path) !== undefined;
}

/**
 * Whether `before` and `after`, `path` at two revisions, or undefined where it is absent, build
 * the same.
 */
export function same(path: string, before: string | undefined, after: string | undefined): boolean {
	if (before === undefined || after === undefined || before === after) return before === after;
	const normalize = normalizer(path);
	return normalize !== undefined && isDeepStrictEqual(normalize(before), normalize(after));
}
