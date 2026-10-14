/**
 * What each crate is built from beyond its repository's files, read at two revisions: the packages
 * it resolves to, and the parts of the root Cargo.toml it inherits. Read by ./deployable.ts, so a
 * change to either rebuilds only the images whose inputs moved. Cargo.lock is read first, as text:
 * a crate whose packages there did not move did not. Every package any member enables lands in the
 * lockfile, so one that did is asked of cargo, which builds each image's crate alone and says what
 * that compiles; where cargo cannot answer, the lockfile's word stands.
 */
import { spawnSync } from 'node:child_process';
import { realpathSync } from 'node:fs';
import { isDeepStrictEqual } from 'node:util';
import { parse } from 'smol-toml';

/** The profile every image is built with, `cargo build --profile container` in each Dockerfile. */
const IMAGE_PROFILE = 'container';

/** What every image is built for: `$arch-unknown-linux-musl` in each Dockerfile. */
const TARGETS = ['aarch64-unknown-linux-musl', 'x86_64-unknown-linux-musl'];

/**
 * Parts of `[workspace]` no image is built from as such: who is a member moves Cargo.lock and the
 * member's own files, both read apart, and lints and metadata change warnings and tools, not output.
 */
const UNBUILT = new Set(['members', 'exclude', 'default-members', 'lints', 'metadata']);

type Table = Record<string, unknown>;

interface Package {
	name: string;
	version: string;
	source?: string;
	checksum?: string;
	dependencies?: string[];
}

const tableOf = (value: unknown): Table =>
	typeof value === 'object' && value !== null && !Array.isArray(value) ? (value as Table) : {};

/** Two sets holding the same members. */
function equal<T>(a: ReadonlySet<T>, b: ReadonlySet<T>): boolean {
	return a.size === b.size && [...a].every((one) => b.has(one));
}

/**
 * Crate -> every package it reaches in the lockfile `lock`, itself included, each as its name,
 * version, source and checksum; undefined for a crate the lockfile does not hold.
 */
export function closures(
	lock: string,
	crates: Iterable<string>,
): Map<string, Set<string> | undefined> {
	const byName = new Map<string, Package[]>();
	for (const one of (parse(lock).package ?? []) as unknown as Package[]) {
		byName.set(one.name, [...(byName.get(one.name) ?? []), one]);
	}

	// `name`, `name version` or `name version (source)`: as much as tells it apart.
	const resolve = (reference: string): Package[] => {
		const [name = '', ...rest] = reference.split(' ');
		const tail = rest.length > 1 ? [rest[0] as string, rest.slice(1).join(' ')] : rest;
		let found = byName.get(name) ?? [];
		if (tail.length) found = found.filter((one) => one.version === tail[0]);
		if (tail.length > 1) {
			const source = (tail[1] as string).replace(/^[()]+|[()]+$/g, '');
			found = found.filter((one) => one.source === source);
		}
		return found;
	};

	const key = (one: Package) =>
		[one.name ?? '', one.version ?? '', one.source ?? '', one.checksum ?? ''].join('\0');

	const result = new Map<string, Set<string> | undefined>();
	for (const crate of crates) {
		const queue = (byName.get(crate) ?? []).filter((one) => one.source === undefined);
		const seen = new Set<string>();
		while (queue.length) {
			const one = queue.pop() as Package;
			if (seen.has(key(one))) continue;
			seen.add(key(one));
			for (const reference of one.dependencies ?? []) queue.push(...resolve(reference));
		}
		result.set(crate, seen.size ? seen : undefined);
	}
	return result;
}

/** The crates of `crates` whose packages differ between the two lockfiles. */
export function lockMoved(base: string, head: string, crates: ReadonlySet<string>): Set<string> {
	const before = closures(base, crates);
	const after = closures(head, crates);
	return new Set(
		[...crates].filter((crate) => {
			const was = before.get(crate);
			const now = after.get(crate);
			return was === undefined || now === undefined ? was !== now : !equal(was, now);
		}),
	);
}

/**
 * What `cargo build -p crate` compiles for an image in `tree`, each package with its features and
 * with paths made relative to the tree; undefined where cargo cannot say.
 */
export function builtFrom(tree: string, crate: string, cwd: string): Set<string> | undefined {
	const root = realpathSync(tree);
	const command = ['tree', '--locked', '--manifest-path', `${root}/Cargo.toml`, '-p', crate];
	command.push('-e', 'normal,build', '--prefix', 'none', '--format', '{p} {f}');
	for (const target of TARGETS) command.push('--target', target);
	const answer = spawnSync('cargo', command, {
		cwd,
		encoding: 'utf8',
		maxBuffer: 64 * 1024 * 1024,
	});
	if (answer.status !== 0) return undefined;
	const lines = answer.stdout.split('\n');
	if (lines.at(-1) === '') lines.pop();
	return new Set(lines.map((line) => line.replaceAll(' (*)', '').replaceAll(root, '')));
}

/**
 * The crates cargo builds from something else in the tree `head` than in `base`; any it cannot
 * read in either counts as moved.
 */
export function treeMoved(
	base: string,
	head: string,
	crates: Iterable<string>,
	cwd: string,
): Set<string> {
	const moved = new Set<string>();
	for (const crate of crates) {
		const before = builtFrom(base, crate, cwd);
		const after = before && builtFrom(head, crate, cwd);
		if (before === undefined || after === undefined || !equal(before, after)) moved.add(crate);
	}
	return moved;
}

/** The profiles an image's build reads, following `inherits` from the image's own. */
function profiles(manifest: Table): Set<string> {
	const declared = tableOf(manifest.profile);
	const chain = new Set(['release']);
	let name: unknown = IMAGE_PROFILE;
	while (typeof name === 'string' && name && !chain.has(name)) {
		chain.add(name);
		name = tableOf(declared[name]).inherits;
	}
	return chain;
}

/** Whether `member` takes `key` of `[workspace.<table>]` with `workspace = true`. */
function inherits(member: Table, table: string, key: string): boolean {
	if (table === 'package')
		return isDeepStrictEqual(tableOf(member.package)[key], { workspace: true });
	const sections = [member, ...Object.values(tableOf(member.target)).map(tableOf)];
	for (const section of sections) {
		for (const kind of ['dependencies', 'dev-dependencies', 'build-dependencies']) {
			const entry = tableOf(section[kind])[key];
			if (tableOf(entry).workspace === true) return true;
		}
	}
	return false;
}

/** Whether any entry under `table` names a `path`. */
function hasPath(table: unknown): boolean {
	if (typeof table !== 'object' || table === null || Array.isArray(table)) return false;
	return 'path' in table || Object.values(table).some(hasPath);
}

const differ = (a: unknown, b: unknown) => !isDeepStrictEqual(a, b);

/** `value`, or an empty table where it is empty or false, as Python's `value or {}` reads it. */
function orEmpty(value: unknown): unknown {
	const empty =
		!value ||
		(Array.isArray(value) && !value.length) ||
		(typeof value === 'object' && !(value instanceof Date) && !Object.keys(value as object).length);
	return empty ? {} : value;
}

/**
 * The crates a change to the root Cargo.toml reaches, or undefined where it reaches every image or
 * cannot be told. `members` maps each crate to its own Cargo.toml, parsed.
 */
export function manifestMoved(
	base: string,
	head: string,
	members: ReadonlyMap<string, Table>,
): Set<string> | undefined {
	const before = parse(base) as Table;
	const after = parse(head) as Table;
	const reached = new Set<string>();
	for (const top of new Set([...Object.keys(before), ...Object.keys(after)])) {
		const old = before[top] ?? {};
		const now = after[top] ?? {};
		if (!differ(old, now)) continue;
		if (top === 'profile') {
			const chain = new Set([...profiles(before), ...profiles(after)]);
			if ([...chain].some((name) => differ(tableOf(old)[name], tableOf(now)[name])))
				return undefined;
		} else if (top === 'patch' || top === 'replace') {
			// One from the registry or git moves Cargo.lock, which is read apart; a path's does not.
			if (hasPath(old) || hasPath(now)) return undefined;
		} else if (top === 'workspace') {
			const was = tableOf(old);
			const is = tableOf(now);
			for (const part of new Set([...Object.keys(was), ...Object.keys(is)])) {
				const from = orEmpty(was[part]);
				const to = orEmpty(is[part]);
				if (!differ(from, to) || UNBUILT.has(part)) continue;
				if (part !== 'dependencies' && part !== 'package') return undefined;
				for (const key of new Set([...Object.keys(tableOf(from)), ...Object.keys(tableOf(to))])) {
					if (differ(tableOf(from)[key], tableOf(to)[key])) {
						for (const [name, one] of members) if (inherits(one, part, key)) reached.add(name);
					}
				}
			}
		} else {
			return undefined;
		}
	}
	return reached;
}
