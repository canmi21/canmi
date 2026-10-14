/**
 * A repository's `update`: its own `[tools]` within their pins, its crates and its packages within
 * their ranges, and with `--major` across them for what ./outdated.ts calls behind -- a package
 * `versions.toml` allows at two majors left on both. See spec/toolchain.md, "Dependencies move the
 * way tools do". `--dry-run` says what would move and writes nothing.
 */
import { spawnSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import { report } from './outdated.ts';

const args = new Set(process.argv.slice(2));
const dry = args.has('--dry-run') || args.has('-n') || process.env.usage_dry_run === 'true';
const major = args.has('--major') || Boolean(process.env.usage_major);
const n = dry ? ['--dry-run'] : [];

/** The tools this repository's own `mise.toml` declares, by name. */
function ownTools(): string[] {
	const names: string[] = [];
	let inside = false;
	for (const line of readFileSync('mise.toml', 'utf8').split('\n')) {
		if (line.startsWith('[')) inside = line.startsWith('[tools]');
		else if (inside) {
			const name = /^([a-z0-9-]*) *=/.exec(line);
			if (name) names.push(name[1] as string);
		}
	}
	return names;
}

/** A command's output as it arrives, and its status. */
const run = (command: string, commandArgs: readonly string[]) =>
	spawnSync(command, commandArgs, { stdio: 'inherit' }).status ?? 1;

const own = ownTools();
console.log(`$ mise upgrade ${own.join('\n')}${dry ? ' --dry-run' : ''}`);
run('mise', ['upgrade', ...own, ...n]);
console.log('');
if (major) {
	if (spawnSync('sh', ['-c', 'command -v cargo-upgrade'], { stdio: 'ignore' }).status === 0) {
		run('cargo', ['upgrade', '--incompatible', ...n]);
	} else {
		console.log("cargo-edit is not installed: the crates' majors were not checked");
	}
}
run('cargo', ['update', ...n]);
console.log('');
if (dry) {
	console.log(report(process.cwd(), false).join('\n'));
	process.exit(0);
}
const names = major ? report(process.cwd(), true) : [];
console.log(`$ pnpm update -r${major ? ` --latest ${names.join(' ')}` : ''}`);
if (major && !names.length) {
	console.log('nothing waits beyond its range');
	process.exit(0);
}
const updated = spawnSync('pnpm', ['update', '-r', ...(major ? ['--latest', ...names] : [])], {
	encoding: 'utf8',
	maxBuffer: 1 << 28,
});
const out = `${updated.stdout ?? ''}${updated.stderr ?? ''}`.replace(/\n$/, '');
console.log(out);
if (updated.status !== 0) {
	if (!out.includes('ERR_PNPM_NO_MATURE_MATCHING_VERSION')) process.exit(1);
	console.log(
		'held by the supply-chain delay, nothing moved in the pnpm half; run again once it has aged',
	);
}
