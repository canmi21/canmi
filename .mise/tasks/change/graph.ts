/**
 * What a change reaches in one repository: its Rust crates and its TypeScript packages, and the
 * edges between them. Read by ./verify.ts, to choose gates, and by ./deployable.ts, to choose
 * images and Workers. Every repository's tasks call it with their own root and layout; a library
 * rather than a task, since it is not executable -- see spec/architecture/repos.md, "A rule that is
 * code inherits the same way, as a module the projects import".
 */
import { execFileSync } from 'node:child_process';
import { existsSync, readdirSync, readFileSync, realpathSync } from 'node:fs';
import { basename, dirname, join, relative, resolve, sep } from 'node:path';

/** Where a repository keeps its apps and packages. */
export interface Layout {
	/** The repository's root, absolute. */
	readonly root: string;
	/** Where a package's manifest sits, as `apps/*\/*` or `libs/*`: one `*` a directory level. */
	readonly packageDirectories: readonly string[];
	/** The directories an app's own directory sits in, relative to the root. */
	readonly appRoots: readonly string[];
}

/** dependency -> its dependents, or path -> what reads it. */
export type Edges = Map<string, Set<string>>;

/** The directories directly under `directory`, sorted, or none where it is not one. */
function subdirectories(directory: string): string[] {
	if (!existsSync(directory)) return [];
	return readdirSync(directory, { withFileTypes: true })
		.filter((entry) => entry.isDirectory())
		.map((entry) => entry.name)
		.toSorted();
}

/** Every directory under `root` a pattern of literal names and `*` names, sorted. */
function expanded(root: string, pattern: string): string[] {
	let found = [root];
	for (const part of pattern.split('/')) {
		found = found.flatMap((at) =>
			part === '*'
				? subdirectories(at).map((name) => join(at, name))
				: existsSync(join(at, part))
					? [join(at, part)]
					: [],
		);
	}
	return found;
}

/** Each group under `apps/`, for a repository that groups its apps; see repos.md, "Grouping threshold". */
export function groupedAppRoots(root: string): string[] {
	return subdirectories(join(root, 'apps')).map((group) => `apps/${group}`);
}

/** Every app directory, absolute, by its name; a name is the app's wherever its layer puts it. */
export function appDirectories(layout: Layout): Map<string, string> {
	const found = new Map<string, string>();
	for (const appRoot of layout.appRoots) {
		for (const name of subdirectories(join(layout.root, appRoot))) {
			found.set(name, join(layout.root, appRoot, name));
		}
	}
	return found;
}

/** The app `path` sits in, by name, or undefined for a path in no app. */
export function appOf(layout: Layout, path: string): string | undefined {
	for (const appRoot of layout.appRoots) {
		if (path.startsWith(`${appRoot}/`)) {
			const rest = path.slice(appRoot.length + 1).split('/');
			return rest.length > 1 ? rest[0] : undefined;
		}
	}
	return undefined;
}

/** Files the working copy changes, or everything after `since`. */
export function changed(root: string, since?: string): string[] {
	const range = since ? ['--from', since, '--to', '@'] : ['-r', '@'];
	const output = execFileSync('jj', ['diff', '--name-only', ...range], {
		cwd: root,
		encoding: 'utf8',
	});
	return output.split('\n').filter(Boolean);
}

/** The deepest of `directories` holding `path`, or undefined. */
export function owner(path: string, directories: Iterable<string>): string | undefined {
	let best: string | undefined;
	for (const directory of directories) {
		if (
			path.startsWith(`${directory}/`) &&
			(best === undefined || directory.length > best.length)
		) {
			best = directory;
		}
	}
	return best;
}

/** `affected` and everything that depends on it, through `edges` of dependency -> dependent. */
export function dependents(affected: Iterable<string>, edges: Edges): Set<string> {
	const seen = new Set(affected);
	const queue = [...seen];
	while (queue.length) {
		for (const dependent of edges.get(queue.pop() as string) ?? []) {
			if (!seen.has(dependent)) {
				seen.add(dependent);
				queue.push(dependent);
			}
		}
	}
	return seen;
}

function add(edges: Edges, key: string, value: string): void {
	const held = edges.get(key);
	if (held) held.add(value);
	else edges.set(key, new Set([value]));
}

/** Every `.rs` file under `directory`, at any depth, but none under a `target` directory. */
function rustSources(directory: string): string[] {
	const found: string[] = [];
	const walk = (at: string) => {
		for (const entry of readdirSync(at, { withFileTypes: true })) {
			const path = join(at, entry.name);
			if (entry.isDirectory()) {
				if (entry.name !== 'target') walk(path);
			} else if (entry.name.endsWith('.rs')) found.push(path);
		}
	};
	if (existsSync(directory)) walk(directory);
	return found.toSorted();
}

const INCLUDE = /include_(?:str|bytes)!\(\s*"([^"]+)"/g;

/** `path` with its links resolved where it exists, as Python's `Path.resolve` reads it. */
function resolved(path: string): string {
	const absolute = resolve(path);
	return existsSync(absolute) ? realpathSync(absolute) : absolute;
}

/** `target` relative to `root`, or undefined where it is outside it. */
function within(root: string, target: string): string | undefined {
	const rest = relative(root, target);
	return rest && !rest.startsWith(`..${sep}`) && rest !== '..'
		? rest.split(sep).join('/')
		: undefined;
}

/** What each of `source`'s include literals names, relative to `root`, where it is inside it. */
function includes(root: string, source: string, text: string): string[] {
	return [...text.matchAll(INCLUDE)]
		.map((match) => within(root, resolved(join(dirname(source), match[1] as string))))
		.filter((path): path is string => path !== undefined);
}

export interface RustGraph {
	/** Crate directory, relative to the root -> the crate's name. */
	directories: Map<string, string>;
	/** Dependency -> dependent, among the repository's own crates. */
	edges: Edges;
	/** File -> the crates whose sources include it, a test's include among them. */
	included: Edges;
}

/** Crate directories, dependency -> dependent edges, and file -> crates that include it. */
export function rustGraph(root: string): RustGraph {
	const metadata = JSON.parse(
		execFileSync('cargo', ['metadata', '--no-deps', '--format-version', '1'], {
			cwd: root,
			encoding: 'utf8',
			maxBuffer: 64 * 1024 * 1024,
		}),
	) as {
		packages: {
			name: string;
			manifest_path: string;
			dependencies: { name: string; path?: string }[];
		}[];
	};
	const real = resolved(root);
	const directories = new Map<string, string>();
	const edges: Edges = new Map();
	const included: Edges = new Map();
	const names = new Set(metadata.packages.map((one) => one.name));
	for (const one of metadata.packages) {
		const directory = dirname(one.manifest_path);
		// The root's own crate is `.`, as a path relative to itself reads.
		directories.set(within(real, resolved(directory)) ?? '.', one.name);
		for (const dependency of one.dependencies) {
			if (dependency.path && names.has(dependency.name)) add(edges, dependency.name, one.name);
		}
		// A test reading another crate's file depends on it without the manifest saying so.
		for (const source of rustSources(directory)) {
			for (const path of includes(real, source, readFileSync(source, 'utf8'))) {
				add(included, path, one.name);
			}
		}
	}
	return { directories, edges, included };
}

/** The path of a module `name` declared out of line in `source`, where either file exists. */
function moduleFile(source: string, name: string): string | undefined {
	const file = basename(source);
	const base = ['lib.rs', 'main.rs', 'mod.rs'].includes(file)
		? dirname(source)
		: join(dirname(source), file.slice(0, -'.rs'.length));
	return [join(base, `${name}.rs`), join(base, name, 'mod.rs')].find((path) => existsSync(path));
}

const TEST_MODULE =
	/#\[cfg\(test\)\]\s*(?:#\[[^\]]*\]\s*)*(?:pub(?:\([^)]*\))?\s+)?mod\s+(\w+)\s*;/g;

/**
 * The files of `sources` that are test modules declared out of line, `#[cfg(test)] mod tests;`,
 * and everything under such a module's own directory.
 */
function testModules(sources: readonly string[]): Set<string> {
	const tests = new Set<string>();
	for (const source of sources) {
		for (const match of readFileSync(source, 'utf8').matchAll(TEST_MODULE)) {
			const file = moduleFile(source, match[1] as string);
			if (!file) continue;
			tests.add(file);
			const below = basename(file) === 'mod.rs' ? dirname(file) : file.slice(0, -'.rs'.length);
			for (const one of sources) if (one.startsWith(`${below}${sep}`)) tests.add(one);
		}
	}
	return tests;
}

/**
 * Path -> crates whose own code, not a test, includes it with `include_str!` or `include_bytes!`:
 * what a binary carries. A test is a file under the crate's `tests/`, an include after a file's
 * first `#[cfg(test)]`, or a module declared `#[cfg(test)] mod name;` in a file of its own.
 */
export function embedded(root: string, directories: Map<string, string>): Edges {
	const real = resolved(root);
	const found: Edges = new Map();
	for (const [directory, crate] of directories) {
		const top = join(real, directory);
		const sources = rustSources(top).filter(
			(source) => !relative(top, source).split(sep).includes('tests'),
		);
		const tests = testModules(sources);
		for (const source of sources) {
			if (tests.has(source)) continue;
			const text = readFileSync(source, 'utf8').split('#[cfg(test)]', 1)[0] as string;
			for (const path of includes(real, source, text)) add(found, path, crate);
		}
	}
	return found;
}

/**
 * Path -> crates whose build script reads it: a relative literal in a `build.rs`, resolved from
 * the crate's directory. What a build script embeds is in the binary as much as its source.
 */
export function buildInputs(root: string, directories: Map<string, string>): Edges {
	const real = resolved(root);
	const inputs: Edges = new Map();
	for (const [directory, crate] of directories) {
		const script = join(real, directory, 'build.rs');
		if (!existsSync(script)) continue;
		for (const match of readFileSync(script, 'utf8').matchAll(/"(\.\.?\/[^"]+)"/g)) {
			const target = resolved(join(real, directory, match[1] as string));
			const path = existsSync(target) ? within(real, target) : undefined;
			if (path !== undefined) add(inputs, path, crate);
		}
	}
	return inputs;
}

export interface NodeGraph {
	/** Package directory, relative to the root -> the package's name. */
	directories: Map<string, string>;
	/** Dependency -> dependent, among the repository's own packages. */
	edges: Edges;
}

/** Package directories and dependency -> dependent edges among the repository's packages. */
export function nodeGraph(layout: Layout): NodeGraph {
	const manifests = new Set<string>();
	for (const pattern of layout.packageDirectories) {
		for (const directory of expanded(layout.root, pattern)) {
			const manifest = join(directory, 'package.json');
			if (existsSync(manifest)) manifests.add(manifest);
		}
	}
	const directories = new Map<string, string>();
	const read = new Map<string, Record<string, Record<string, string> | undefined>>();
	for (const manifest of [...manifests].toSorted()) {
		const data = JSON.parse(readFileSync(manifest, 'utf8'));
		directories.set(relative(layout.root, dirname(manifest)).split(sep).join('/'), data.name);
		read.set(data.name, data);
	}
	const edges: Edges = new Map();
	for (const [name, data] of read) {
		for (const field of ['dependencies', 'devDependencies', 'peerDependencies']) {
			for (const dependency of Object.keys(data[field] ?? {})) {
				if (read.has(dependency)) add(edges, dependency, name);
			}
		}
	}
	return { directories, edges };
}
