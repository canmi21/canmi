/**
 * A repository's `clean`: remove what cargo and the JavaScript tools built, never an installed
 * dependency or local state. A path goes only when a tool writes it, git ignores it and nothing
 * under it is tracked -- spec/toolchain.md, "A cache is what a tool can write again". Inside
 * node_modules only what tools dropped there goes; `.wrangler/state` is a local D1, KV and R2, and
 * `.vercel` keeps the project link, so only `.wrangler/tmp` and `.vercel/output` go. Arguments
 * name further caches the repository's own tools write, relative to its root.
 */
import { execFileSync, spawnSync } from 'node:child_process';
import { existsSync, lstatSync, rmSync, statSync } from 'node:fs';
import { join } from 'node:path';

/** What `find` lists from `root`, a path a line, as the shell's `find` loops read them. */
function find(root: string, ...args: string[]): string[] {
	return execFileSync('find', ['.', ...args], { cwd: root, encoding: 'utf8', maxBuffer: 1 << 28 })
		.split('\n')
		.filter(Boolean);
}

const PRUNED = ['-name', '.git', '-o', '-name', '.jj', '-o', '-name', 'target'];

/** Every path a tool may have written, in the order the shell version found them. */
export function candidates(root: string, extra: readonly string[] = []): string[] {
	const built = find(
		root,
		'(',
		...PRUNED,
		'-o',
		'-name',
		'node_modules',
		'-o',
		'-name',
		'.wrangler',
		'-o',
		'-name',
		'.vercel',
		')',
		'-prune',
		'-o',
		'-type',
		'd',
		'(',
		'-name',
		'.svelte-kit',
		'-o',
		'-name',
		'dist',
		'-o',
		'-name',
		'build',
		'-o',
		'-name',
		'coverage',
		'-o',
		'-name',
		'.turbo',
		'-o',
		'-name',
		'.output',
		'-o',
		'-name',
		'__pycache__',
		')',
		'-print',
		'-prune',
	);
	const installed = find(
		root,
		'(',
		...PRUNED,
		')',
		'-prune',
		'-o',
		'-name',
		'node_modules',
		'-prune',
		'-print',
	);
	const dropped = installed.flatMap((one) =>
		lstatSync(join(root, one)).isSymbolicLink()
			? []
			: ['.vite', '.vite-temp', '.cache', '.vitest', '.svelte2tsx-language-server-files']
					.map((cache) => `${one}/${cache}`)
					.filter((path) => statSync(join(root, path), { throwIfNoEntry: false })?.isDirectory()),
	);
	const below = (name: string, keep: string) =>
		find(
			root,
			'(',
			...PRUNED,
			'-o',
			'-name',
			'node_modules',
			')',
			'-prune',
			'-o',
			'-type',
			'd',
			'-name',
			name,
			'-prune',
			'-print',
		).map((dir) => `${dir}/${keep}`);
	return [
		...built,
		...dropped,
		...extra.map((path) => `./${path}`),
		...below('.wrangler', 'tmp'),
		...below('.vercel', 'output'),
	];
}

/** `du -sh`'s size of `path`, as the shell version printed it. */
function size(root: string, path: string): string {
	const answer = spawnSync('du', ['-sh', path], { cwd: root, encoding: 'utf8' });
	return (answer.stdout ?? '').trim().split(/\s+/)[0] ?? '';
}

/** The task: `clean [--dry-run] [extra cache...]`, from the repository's root. */
export function main(root = process.cwd(), args: readonly string[] = process.argv.slice(2)): void {
	const dry =
		args.includes('--dry-run') || args.includes('-n') || process.env.usage_dry_run === 'true';
	const extra = args.filter((arg) => !arg.startsWith('-'));
	if (dry) {
		console.log(
			`would run cargo clean, ${existsSync(join(root, 'target')) ? size(root, 'target') : ''}`,
		);
	} else if (spawnSync('cargo', ['clean'], { cwd: root, stdio: 'inherit' }).status !== 0) {
		process.exit(1);
	}
	let found = false;
	for (const path of candidates(root, extra)) {
		if (!existsSync(join(root, path))) continue;
		if (spawnSync('git', ['check-ignore', '-q', path], { cwd: root }).status !== 0) continue;
		const tracked = spawnSync('git', ['ls-files', '--', path], {
			cwd: root,
			encoding: 'utf8',
		}).stdout;
		if (tracked.trim()) continue;
		found = true;
		if (dry) {
			console.log(`would remove ${path}, ${size(root, path)}`);
		} else {
			rmSync(join(root, path), { recursive: true, force: true });
			console.log(`removed ${path}`);
		}
	}
	if (!found) console.log('no tool caches to remove');
}

if (import.meta.main) main();
