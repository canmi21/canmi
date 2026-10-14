/**
 * A repository's `fmt`: rustfmt over its crates where it has any, then oxfmt over the files its
 * glob names; `--dry-run` lists what either would change and fails nothing. `--glob` replaces the
 * default glob, for a repository that formats fewer kinds of file.
 */
import { spawnSync } from 'node:child_process';
import { existsSync } from 'node:fs';

const GLOB = '**/*.{ts,tsx,mts,cts,js,mjs,cjs,jsx,css,json,jsonc,md,svelte}';

const args = process.argv.slice(2);
const flags = new Set(args);
const dry = flags.has('--dry-run') || flags.has('-n') || process.env.usage_dry_run === 'true';
const glob = flags.has('--glob') ? (args[args.indexOf('--glob') + 1] as string) : GLOB;

/** One command; a failure ends the task unless it is only a report, as a dry run's are. */
function step(command: string, commandArgs: readonly string[]): void {
	const ran = spawnSync(command, commandArgs, { stdio: 'inherit' });
	if (!dry && ran.status !== 0) process.exit(ran.status ?? 1);
}

if (existsSync('Cargo.toml')) {
	step('cargo', dry ? ['fmt', '--all', '--check', '--message-format', 'short'] : ['fmt', '--all']);
}
step('oxfmt', [...(dry ? ['--list-different'] : []), '--no-error-on-unmatched-pattern', glob]);
