/**
 * The gates a change has to pass, chosen by what it touched, each repository calling it with its
 * own gates. See spec/architecture/repos.md, "verify runs what a change reaches".
 */
import { spawnSync } from 'node:child_process';
import { existsSync } from 'node:fs';
import { extname, join } from 'node:path';
import {
	appOf,
	buildInputs,
	changed,
	dependents,
	type Layout,
	nodeGraph,
	owner,
	rustGraph,
} from './graph.ts';

/** A repository's gates, as its own `verify` task names them. */
export interface Config {
	readonly layout: Layout;
	/** Whole-tree and cheap, so they run whatever changed. */
	readonly always: readonly string[];
	/** Whole-program by nature: tsc, vitest and oxlint read everything they read. */
	readonly node: readonly string[];
	/** Gates that belong to one package, run when it or anything it imports changed. */
	readonly packageGates: Readonly<Record<string, readonly string[]>>;
	readonly rust: readonly string[];
	/** The tasks' own tests, run only when everything is. */
	readonly tasks: readonly string[];
	/** Rust files whose only check is a TypeScript test, as a generated mirror is. */
	readonly nodeCheckedRust?: readonly string[];
	/** What a file reaches that no graph shows: packages or crates read rather than imported. */
	readonly reaches?: (path: string) => { packages?: readonly string[]; crates?: readonly string[] };
}

const NODE_SUFFIXES = new Set([
	'.ts',
	'.js',
	'.mjs',
	'.cjs',
	'.svelte',
	'.css',
	'.json',
	'.html',
	'.yaml',
	'.yml',
]);
/** The gates themselves: a change to how anything is checked is checked against everything. */
const GATE_FILES = ['mise.toml', '.mise/tasks/'] as const;
const NODE_ROOT_FILES = new Set([
	'package.json',
	'pnpm-lock.yaml',
	'pnpm-workspace.yaml',
	'vitest.config.ts',
]);
const RUST_ROOT_FILES = new Set(['Cargo.toml', 'Cargo.lock']);

/** Every gate the repository has, in the order they run. */
export function everything(config: Config): string[] {
	return [
		...config.always,
		...config.node,
		...Object.values(config.packageGates).flat(),
		...config.rust,
		...config.tasks,
	];
}

export interface Plan {
	gates: string[];
	/** The Rust packages to run them over, undefined meaning all. */
	crates: Set<string> | undefined;
	/** Why every gate runs, where every gate does. */
	reason?: string;
}

/** The gates to run for `files`, and the Rust packages to run them over. */
export function plan(config: Config, files: readonly string[]): Plan {
	if (files.some((file) => file === GATE_FILES[0] || file.startsWith(GATE_FILES[1]))) {
		return { gates: everything(config), crates: undefined, reason: 'the gates themselves changed' };
	}
	const { layout } = config;
	const { directories: crateDirs, edges: crateEdges, included } = rustGraph(layout.root);
	const built = buildInputs(layout.root, crateDirs);
	const { directories: packageDirs, edges: packageEdges } = nodeGraph(layout);
	const crates = new Set<string>();
	const packages = new Set<string>();
	const gates = [...config.always];
	let allCrates = false;
	let allPackages = false;

	for (const file of files) {
		const suffix = extname(file);
		if (RUST_ROOT_FILES.has(file) || file === 'rust-toolchain.toml') allCrates = true;
		for (const crate of included.get(file) ?? []) crates.add(crate);
		for (const crate of built.get(owner(file, built.keys()) ?? file) ?? []) crates.add(crate);
		const reach = config.reaches?.(file) ?? {};
		for (const crate of reach.crates ?? []) crates.add(crate);
		for (const name of reach.packages ?? []) packages.add(name);
		const crate = crateDirs.get(owner(file, crateDirs.keys()) ?? '');
		if (crate && (suffix === '.rs' || file.endsWith('/Cargo.toml'))) crates.add(crate);

		if (NODE_ROOT_FILES.has(file) || file.startsWith('tsconfig')) allPackages = true;
		const found = packageDirs.get(owner(file, packageDirs.keys()) ?? '');
		if (found && (NODE_SUFFIXES.has(suffix) || config.nodeCheckedRust?.includes(file))) {
			packages.add(found);
		}
	}

	const reachedPackages = allPackages
		? new Set(packageDirs.values())
		: dependents(packages, packageEdges);
	if (reachedPackages.size) {
		gates.push(...config.node);
		for (const [name, owned] of Object.entries(config.packageGates)) {
			if (reachedPackages.has(name)) gates.push(...owned);
		}
	}
	const reachedCrates = allCrates ? undefined : dependents(crates, crateEdges);
	if (allCrates || reachedCrates?.size) gates.push(...config.rust);
	return { gates, crates: reachedCrates };
}

/** Whether `path` is an app's declaration, `service.toml` in any app's tree. */
export function isDeclaration(layout: Layout, path: string): boolean {
	return appOf(layout, path) !== undefined && path.endsWith('/service.toml');
}

/** A repository's `verify` task: the gates printed, then run, every one reporting. */
export function main(config: Config, args: readonly string[] = process.argv.slice(2)): void {
	const { root } = config.layout;
	// A library taken from the checkout beside this one is a state for trying a change, never one
	// to pass in: what it installed is nowhere a clone can reach. See .mise/tasks/lib-local.
	if (existsSync(join(root, '.local', 'lib'))) {
		console.error('verify: the library is local; `mise run lib-local --off` first');
		process.exit(1);
	}
	const dry = args.includes('--dry-run') || args.includes('-n');
	const since = args.includes('--since') ? args[args.indexOf('--since') + 1] : undefined;
	// `--files a b` asks what a change to exactly those files would run, without making it.
	const given = args.includes('--files') ? args.slice(args.indexOf('--files') + 1) : undefined;

	let chosen: Plan;
	if (args.includes('--all') || process.env.AUDIT) {
		chosen = { gates: everything(config), crates: undefined, reason: 'asked for everything' };
	} else {
		const files = given ?? changed(root, since);
		chosen = plan(config, files);
		const where = given ? 'given' : since ? `since ${since}` : 'in the working copy';
		console.log(`verify: ${files.length} file(s) ${where}`);
	}
	const { gates, crates, reason } = chosen;
	if (reason) console.log(`verify: every gate, because ${reason}`);
	const scope = crates === undefined ? 'every crate' : [...crates].toSorted().join(', ') || 'none';
	if (gates.includes('lint-rust')) console.log(`verify: Rust over ${scope}`);
	console.log(`verify: ${gates.join(' ')}`);
	if (dry) return;

	const environment = { ...process.env };
	if (crates !== undefined) {
		environment.RUST_PACKAGES = [...crates]
			.toSorted()
			.map((crate) => `-p ${crate}`)
			.join(' ');
	}
	// Every gate reports, not only the first to fail: a red run is worth its whole list.
	const command = ['run', '--continue-on-error', gates[0] as string];
	for (const gate of gates.slice(1)) command.push(':::', gate);
	const ran = spawnSync('mise', command, { cwd: root, env: environment, stdio: 'inherit' });
	process.exit(ran.status ?? 1);
}
