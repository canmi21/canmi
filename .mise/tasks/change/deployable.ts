/**
 * What a change needs built, as JSON, for the repository that calls it: images, declarations to
 * apply alone, or Workers. An app with a `service.toml` and a `Dockerfile` needs a new image when
 * what goes into it changed, each read as a build reads it (./fingerprint.ts): a crate it is built
 * from, a file its binary includes, a package Cargo.lock resolves it to, its Dockerfile, or the
 * build. A declaration changed alone needs none; `--declared` lists those. A Worker, an app placed
 * on `workers` with a `wrangler.jsonc`, needs packaging when it, a package it imports, or the
 * packaging changed. See repos/infra/spec/architecture/host.md, "The machine pulls; nothing pushes
 * into it", and repos/platform/spec/architecture/deployer.md, "What a Worker artifact is".
 */
import { execFileSync, spawnSync } from 'node:child_process';
import { existsSync, mkdtempSync, readFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { parse } from 'smol-toml';
import { ignored, normalized, same } from './fingerprint.ts';
import {
	appDirectories,
	appOf,
	buildInputs,
	changed,
	dependents,
	embedded,
	type Layout,
	nodeGraph,
	owner,
	rustGraph,
} from './graph.ts';
import { movedImporters } from './lockfile.ts';
import { lockMoved, manifestMoved, treeMoved } from './resolved.ts';

/** How every image is built: a change here is a change to all of them. */
const EVERY_IMAGE = new Set(['.dockerignore', '.mise/tasks/image']);
/**
 * What every image is resolved from, read at both revisions so only the images whose inputs moved
 * are rebuilt; see ./resolved.ts. Given files alone, with no base to read, every image, as above.
 */
const RESOLUTION = new Set(['Cargo.toml', 'Cargo.lock']);
/** What a Dockerfile copies from the context when its image is its crate's binary and nothing else. */
const WORKSPACE = new Set(['Cargo.toml', 'Cargo.lock', 'apps', 'libs']);
/** What every Node image installs from, read by importer; see ./lockfile.ts. */
const LOCKFILE = 'pnpm-lock.yaml';
/** How every Worker is packaged, the same. */
const EVERY_WORKER = new Set([
	'package.json',
	'pnpm-lock.yaml',
	'pnpm-workspace.yaml',
	'.mise/tasks/worker',
]);

/** What a repository builds, as its own `deployable` task says. */
export interface Config {
	readonly layout: Layout;
	/** Whether its apps have images; one without them lists its Workers whatever it is asked. */
	readonly images: boolean;
	/** Its Workers, or false for a repository with none; `only` narrows them to those named. */
	readonly workers: false | { readonly only?: ReadonlySet<string> };
}

/** App name -> its crate's or its package's name, for what a run builds. */
export type Declared = Map<string, string | null>;

/** App directory name -> its crate's name, for every app that declares an image. */
export function apps(layout: Layout): Declared {
	const found: Declared = new Map();
	for (const [name, directory] of appDirectories(layout)) {
		if (
			!existsSync(join(directory, 'service.toml')) ||
			!existsSync(join(directory, 'Dockerfile'))
		) {
			continue;
		}
		const manifest = join(directory, 'Cargo.toml');
		const line = existsSync(manifest)
			? readFileSync(manifest, 'utf8')
					.split('\n')
					.find((one) => one.startsWith('name = '))
			: undefined;
		found.set(name, line?.split('"')[1] ?? name);
	}
	return found;
}

/** App directory name -> its package's name, for every Workers app with a wrangler.jsonc. */
export function workers(layout: Layout, only?: ReadonlySet<string>): Declared {
	const found: Declared = new Map();
	for (const [name, directory] of appDirectories(layout)) {
		const declared = join(directory, 'service.toml');
		if (only && !only.has(name)) continue;
		if (!existsSync(declared) || !existsSync(join(directory, 'wrangler.jsonc'))) continue;
		const placements = parse(readFileSync(declared, 'utf8')).placements ?? [];
		if (!(placements as unknown[]).includes('workers')) continue;
		const manifest = join(directory, 'package.json');
		found.set(name, existsSync(manifest) ? JSON.parse(readFileSync(manifest, 'utf8')).name : null);
	}
	return found;
}

/** Files changed between `base` and `head`, for CI, where there is git and no jj. */
export function gitChanged(root: string, base: string, head = 'HEAD'): string[] {
	const output = execFileSync('git', ['diff', '--name-only', base, head], {
		cwd: root,
		encoding: 'utf8',
	});
	return output.split('\n').filter(Boolean);
}

/** A side of a comparison, as `needed` and `redeclared` read one. */
export interface Readable {
	read(path: string): string | undefined;
	tree?(): string;
}

/** Temporary trees written for cargo, gone when the process is. */
const temporary: string[] = [];
process.on('exit', () => {
	for (const tree of temporary) rmSync(tree, { recursive: true, force: true });
});

/**
 * One side of a comparison: the commit `commit` names, or the files on disk where it is undefined.
 * Its whole tree is written out once, the first time cargo is asked about it.
 */
export class Revision implements Readable {
	private readonly root: string;
	private readonly commit: string | undefined;
	private written: string | undefined;

	constructor(root: string, commit?: string) {
		this.root = root;
		this.commit = commit;
	}

	read(path: string): string | undefined {
		if (this.commit === undefined) {
			const file = join(this.root, path);
			return existsSync(file) ? readFileSync(file, 'utf8') : undefined;
		}
		const answer = spawnSync('git', ['show', `${this.commit}:${path}`], {
			cwd: this.root,
			encoding: 'utf8',
			maxBuffer: 256 * 1024 * 1024,
		});
		return answer.status === 0 ? answer.stdout : undefined;
	}

	tree(): string {
		if (this.commit === undefined) return this.root;
		if (this.written === undefined) {
			this.written = mkdtempSync(join(tmpdir(), 'deployable-'));
			temporary.push(this.written);
			const archive = execFileSync('git', ['archive', this.commit], {
				cwd: this.root,
				maxBuffer: 1024 * 1024 * 1024,
			});
			execFileSync('tar', ['-x', '-C', this.written], { input: archive });
		}
		return this.written;
	}
}

/** The git commit a jj revision is, in a colocated repository. */
export function jjCommit(root: string, revision: string): string {
	return execFileSync('jj', ['log', '--no-graph', '-r', revision, '-T', 'commit_id'], {
		cwd: root,
		encoding: 'utf8',
	});
}

type Revisions = readonly [Readable, Readable] | undefined;

/** The tree `side` is written out as, for cargo; a side that cannot write one throws. */
function treeOf(side: Readable): string {
	if (!side.tree) throw new Error('this side of the comparison has no tree to give cargo');
	return side.tree();
}

/**
 * The crates a change to Cargo.lock or the root Cargo.toml reaches, or undefined for every image:
 * given no revisions to read, or where either file cannot be read or told apart. A crate the
 * lockfile moves is asked of cargo, and kept where cargo cannot answer.
 */
function resolution(
	root: string,
	files: readonly string[],
	declared: Declared,
	crateDirs: Map<string, string>,
	revisions: Revisions,
): Set<string> | undefined {
	const touched = new Set(files.filter((file) => RESOLUTION.has(file)));
	if (!touched.size) return new Set();
	if (revisions === undefined) return undefined;
	const [base, head] = revisions;
	const moved = new Set<string>();
	try {
		if (touched.has('Cargo.lock')) {
			const before = base.read('Cargo.lock');
			const after = head.read('Cargo.lock');
			if (before === undefined || after === undefined) return undefined;
			const crates = new Set([...declared.values()].filter((crate): crate is string => !!crate));
			const candidates = lockMoved(before, after, crates);
			if (candidates.size) {
				let reached = candidates;
				try {
					reached = treeMoved(treeOf(base), treeOf(head), candidates, root);
				} catch {
					// Where cargo cannot be asked, the lockfile's word stands.
				}
				for (const crate of reached) moved.add(crate);
			}
		}
		if (touched.has('Cargo.toml')) {
			const before = base.read('Cargo.toml');
			const after = head.read('Cargo.toml');
			if (before === undefined || after === undefined) return undefined;
			const members = new Map(
				[...crateDirs].map(([directory, crate]) => [
					crate,
					parse(readFileSync(join(root, directory, 'Cargo.toml'), 'utf8')) as Record<
						string,
						unknown
					>,
				]),
			);
			const reached = manifestMoved(before, after, members);
			if (reached === undefined) return undefined;
			for (const crate of reached) moved.add(crate);
		}
	} catch {
		return undefined;
	}
	return moved;
}

/**
 * What `dockerfile` copies from the build's context, or undefined where it cannot be told: every
 * source of a `COPY` or `ADD` without `--from`, but an address `ADD` fetches.
 */
export function copied(dockerfile: string): Set<string> | undefined {
	const sources = new Set<string>();
	for (const line of dockerfile.replaceAll('\\\n', ' ').split(/\r\n|\r|\n/)) {
		const words = line.split(/\s+/).filter(Boolean);
		if (!words.length || !['COPY', 'ADD'].includes((words[0] as string).toUpperCase())) continue;
		if (words.some((one) => one.startsWith('['))) return undefined;
		if (words.some((one) => one.startsWith('--from'))) continue;
		const named = words
			.slice(1)
			.filter((one) => !one.startsWith('--'))
			.slice(0, -1);
		for (const one of named) if (!one.includes('://')) sources.add(one);
	}
	return sources;
}

/**
 * The apps whose image is their crate's binary alone: a crate of the workspace, with a Dockerfile
 * copying nothing from the context but the workspace.
 */
export function cargoBuilt(
	layout: Layout,
	declared: Declared,
	crateDirs: Map<string, string>,
): Set<string> {
	const crates = new Set(crateDirs.values());
	const found = new Set<string>();
	for (const [app, directory] of appDirectories(layout)) {
		const crate = declared.get(app);
		if (!declared.has(app) || !crate || !crates.has(crate)) continue;
		const sources = copied(readFileSync(join(directory, 'Dockerfile'), 'utf8'));
		if (sources !== undefined && [...sources].every((one) => WORKSPACE.has(one))) found.add(app);
	}
	return found;
}

/**
 * Those of `files` that change a build: not ignored and, with revisions to read them at, not the
 * same once each is read as a build reads it.
 */
function changes(
	files: readonly string[],
	crateDirs: Iterable<string>,
	revisions: Revisions,
): string[] {
	const dirs = [...crateDirs];
	const kept = files.filter((file) => !ignored(file, dirs));
	if (revisions === undefined) return kept;
	const [base, head] = revisions;
	return kept.filter((file) => !normalized(file) || !same(file, base.read(file), head.read(file)));
}

/** Whether `path` is an app's own `service.toml`, directly in its directory. */
export function declaration(layout: Layout, path: string): boolean {
	const app = appOf(layout, path);
	return app !== undefined && path.endsWith(`/${app}/service.toml`);
}

/** The apps `files` need rebuilt; `revisions` reads a file before and after, as [base, head]. */
export function needed(
	layout: Layout,
	files: readonly string[],
	declared: Declared,
	revisions?: Revisions,
): string[] {
	const { directories: crateDirs, edges: crateEdges } = rustGraph(layout.root);
	const moving = changes(files, crateDirs.keys(), revisions);
	if (moving.some((file) => EVERY_IMAGE.has(file))) return [...declared.keys()].toSorted();
	const built = buildInputs(layout.root, crateDirs);
	// A file a binary includes outside its tests is that crate's source, a declaration among them,
	// and is in the binary byte for byte, as is what a build script reads.
	const carried = embedded(layout.root, crateDirs);
	const crates = new Set<string>();
	const chosen = new Set<string>();
	for (const file of files) {
		for (const crate of built.get(owner(file, built.keys()) ?? file) ?? []) crates.add(crate);
		for (const crate of carried.get(file) ?? []) crates.add(crate);
	}
	const binary = cargoBuilt(layout, declared, crateDirs);
	for (const file of moving) {
		const app = appOf(layout, file);
		const own = app !== undefined && declared.has(app);
		if (own && !declaration(layout, file) && (!binary.has(app) || file.endsWith('/Dockerfile'))) {
			chosen.add(app);
		}
		const crate = crateDirs.get(owner(file, crateDirs.keys()) ?? '');
		if (crate && (file.endsWith('.rs') || file.endsWith('/Cargo.toml'))) crates.add(crate);
	}
	for (const app of imported(layout, moving, declared, binary, revisions)) chosen.add(app);
	const moved = resolution(layout.root, files, declared, crateDirs, revisions);
	if (moved === undefined) return [...declared.keys()].toSorted();
	const reached = dependents(new Set([...crates, ...moved]), crateEdges);
	for (const [app, crate] of declared) if (crate !== null && reached.has(crate)) chosen.add(app);
	return [...chosen].toSorted();
}

/**
 * The apps of `declared` built from their package rather than a crate's binary, the executor and
 * the deployer, whose package imports a package of the repository that `moving` changed: its
 * code is bundled into the image as much as the app's own. A lockfile change counts for the
 * packages whose importer it moved, and for every one where `revisions` cannot tell. RFC l6r4u.
 */
function imported(
	layout: Layout,
	moving: readonly string[],
	declared: Declared,
	binary: ReadonlySet<string>,
	revisions: Revisions,
): Set<string> {
	const { directories, edges } = nodeGraph(layout);
	const changedPackages = new Set<string>();
	if (moving.includes(LOCKFILE)) {
		const before = revisions?.[0].read(LOCKFILE);
		const after = revisions?.[1].read(LOCKFILE);
		const moved =
			before === undefined || after === undefined ? undefined : movedImporters(before, after);
		for (const [directory, name] of directories) {
			if (moved === undefined || moved.has(directory)) changedPackages.add(name);
		}
	}
	for (const file of moving) {
		// A declaration is host's to read, never bundled, as an app's own is above.
		if (declaration(layout, file)) continue;
		const found = directories.get(owner(file, directories.keys()) ?? '');
		if (found) changedPackages.add(found);
	}
	const chosen = new Set<string>();
	if (!changedPackages.size) return chosen;
	const reached = dependents(changedPackages, edges);
	for (const [directory, name] of directories) {
		const app = appOf(layout, `${directory}/package.json`);
		if (app !== undefined && declared.has(app) && !binary.has(app) && reached.has(name)) {
			chosen.add(app);
		}
	}
	return chosen;
}

/**
 * The apps whose `service.toml` is among `files`, its value changed where `revisions` can tell, and
 * whose image is not among `rebuilt`: a declaration to apply over the image the node already runs.
 */
export function redeclared(
	layout: Layout,
	files: readonly string[],
	declared: Declared,
	rebuilt: readonly string[],
	revisions?: Revisions,
): string[] {
	const moving = revisions === undefined ? files : changes(files, [], revisions);
	const touched = new Set(
		moving
			.filter((file) => declaration(layout, file) && declared.has(appOf(layout, file) as string))
			.map((file) => appOf(layout, file) as string),
	);
	return [...touched].filter((app) => !rebuilt.includes(app)).toSorted();
}

/** The Workers `files` need packaged. */
export function neededWorkers(
	layout: Layout,
	files: readonly string[],
	declared: Declared,
): string[] {
	if (files.some((file) => EVERY_WORKER.has(file))) return [...declared.keys()].toSorted();
	const { directories: packageDirs, edges: packageEdges } = nodeGraph(layout);
	const packages = new Set<string>();
	const chosen = new Set<string>();
	for (const file of files) {
		const app = appOf(layout, file);
		if (app !== undefined && declared.has(app)) chosen.add(app);
		const found = packageDirs.get(owner(file, packageDirs.keys()) ?? '');
		if (found) packages.add(found);
	}
	const reached = dependents(packages, packageEdges);
	for (const [app, name] of declared) if (name !== null && reached.has(name)) chosen.add(app);
	return [...chosen].toSorted();
}

/**
 * The files a change touched and the revisions to read them at, as the arguments name them:
 * `--files` alone has no revisions, `--git` compares two commits, and neither compares the working
 * copy with `--since` or its parent.
 */
export function inputs(root: string, args: readonly string[]): [string[], Revisions] {
	const after = (flag: string) => args[args.indexOf(flag) + 1];
	if (args.includes('--files')) return [args.slice(args.indexOf('--files') + 1), undefined];
	if (args.includes('--git')) {
		const base = after('--git') as string;
		const head = args.includes('--head') ? (after('--head') as string) : 'HEAD';
		// HEAD is what CI checked out, so its tree is the one on disk.
		const later = new Revision(root, head === 'HEAD' ? undefined : head);
		return [gitChanged(root, base, head), [new Revision(root, base), later]];
	}
	const since = args.includes('--since') ? after('--since') : undefined;
	const files = changed(root, since);
	try {
		return [files, [new Revision(root, jjCommit(root, since ?? '@-')), new Revision(root)]];
	} catch {
		return [files, undefined];
	}
}

/** The list a repository's `deployable` prints for `args`. */
export function deployable(config: Config, args: readonly string[]): string[] {
	const { layout } = config;
	if (args.includes('--declared')) {
		if (!config.images) throw new Error('--declared lists images, and this repository builds none');
		// Everything rebuilt leaves no declaration to apply alone.
		if (args.includes('--all')) return [];
		const declared = apps(layout);
		const [files, revisions] = inputs(layout.root, args);
		return redeclared(
			layout,
			files,
			declared,
			needed(layout, files, declared, revisions),
			revisions,
		);
	}
	const worker = !config.images || args.includes('--workers');
	if (worker && config.workers === false) {
		throw new Error('--workers lists Workers, and this repository packages none');
	}
	const declared = worker && config.workers ? workers(layout, config.workers.only) : apps(layout);
	if (args.includes('--all')) return [...declared.keys()].toSorted();
	const [files, revisions] = inputs(layout.root, args);
	return worker
		? neededWorkers(layout, files, declared)
		: needed(layout, files, declared, revisions);
}

/** A repository's `deployable` task: the list as JSON on stdout, or the reason on stderr. */
export function main(config: Config, args: readonly string[] = process.argv.slice(2)): void {
	try {
		console.log(JSON.stringify(deployable(config, args)));
	} catch (error) {
		console.error(`deployable: ${error instanceof Error ? error.message : String(error)}`);
		process.exit(1);
	}
}
