/**
 * What waits beyond a repository's package ranges, judged by the newest version it holds anywhere:
 * a package is out of date only when that is older than the registry's latest. One on the latest
 * somewhere while another copy holds an older major is two majors at once, a warning unless
 * `versions.toml` allows it. `--names` prints only what `update --major` should move. See
 * spec/toolchain.md, "A package at two majors is a warning unless it is allowed".
 */
import { spawnSync } from 'node:child_process';
import { existsSync, readFileSync } from 'node:fs';
import { join } from 'node:path';

/** `versions.toml`'s `[several]`: package name -> why it may hold two majors. */
export function allowed(text: string): Map<string, string> {
	const found = new Map<string, string>();
	let section: string | undefined;
	for (const raw of text.split(/\r?\n/)) {
		const line = raw.trim();
		if (!line || line.startsWith('#')) continue;
		if (line.startsWith('[')) {
			section = line.replace(/^\[+|\]+$/g, '');
			continue;
		}
		const match = /^("?)([^"=\s]+)\1\s*=\s*"(.*)"$/.exec(line);
		if (section === 'several' && match)
			found.set(match[2] as string, (match[3] as string).replaceAll('\\"', '"'));
	}
	return found;
}

/** A version as something to sort by: its numbers, then a release above any prerelease of it. */
export function key(version: string): number[] {
	const dash = version.indexOf('-');
	const core = dash < 0 ? version : version.slice(0, dash);
	const numbers = core.split('.').map((part) => (/^\d+$/.test(part) ? Number(part) : 0));
	return [...numbers, dash < 0 ? 1 : 0];
}

/** -1, 0 or 1 as `a` sorts before, with or after `b`, as Python compares two tuples. */
export function compare(a: string, b: string): number {
	const [x, y] = [key(a), key(b)];
	for (let index = 0; index < Math.min(x.length, y.length); index++) {
		if (x[index] !== y[index]) return (x[index] as number) < (y[index] as number) ? -1 : 1;
	}
	return Math.sign(x.length - y.length);
}

/** The part a `^` range holds: the first non-zero number, as `^0.x` does. */
export function major(version: string): string {
	const parts = (version.split('-')[0] as string).split('.');
	const index = parts.findIndex((part) => part !== '0');
	return index < 0 ? version : parts.slice(0, index + 1).join('.');
}

/** The newest of `versions`, the first of equals, as Python's `max` keeps it. */
const newest = (versions: Iterable<string>) =>
	[...versions].reduce((best, one) => (compare(one, best) > 0 ? one : best));

function run(root: string, ...command: string[]): string {
	return (
		spawnSync(command[0] as string, command.slice(1), {
			cwd: root,
			encoding: 'utf8',
			maxBuffer: 1 << 28,
		}).stdout ?? ''
	);
}

type Held = Map<string, Map<string, Set<string>>>;

/** Package name -> version -> the repository's packages that hold it directly. */
function held(root: string): Held {
	const versions: Held = new Map();
	const projects = JSON.parse(
		run(root, 'pnpm', 'list', '-r', '--depth', '0', '--json') || '[]',
	) as {
		name?: string;
		[group: string]: unknown;
	}[];
	for (const project of projects) {
		for (const group of ['dependencies', 'devDependencies', 'optionalDependencies']) {
			const entries = (project[group] ?? {}) as Record<string, { version?: string }>;
			for (const [name, info] of Object.entries(entries)) {
				const version = info.version ?? '';
				if (!version || /^(link:|file:|workspace:)/.test(version)) continue;
				const byVersion = versions.get(name) ?? new Map<string, Set<string>>();
				versions.set(name, byVersion);
				const holders = byVersion.get(version) ?? new Set<string>();
				byVersion.set(version, holders);
				holders.add(project.name ?? '?');
			}
		}
	}
	return versions;
}

const sorted = <T>(values: Iterable<T>) => [...values].toSorted();
const byVersion = (versions: Iterable<string>) => [...versions].toSorted(compare);

/** The report, as lines, or with `names` only the names `update --major` should move. */
export function report(root: string, names: boolean): string[] {
	const versions = held(root);
	const path = join(root, 'versions.toml');
	const several = allowed(existsSync(path) ? readFileSync(path, 'utf8') : '');
	const outdated = JSON.parse(
		run(root, 'pnpm', 'outdated', '-r', '--format', 'json') || '{}',
	) as Record<string, { current: string; latest: string; dependentPackages: { name: string }[] }>;
	const behind: [string, string, string, string[]][] = [];
	const split: [string, Map<string, Set<string>>][] = [];
	for (const name of sorted(Object.keys(outdated))) {
		const entry = outdated[name] as (typeof outdated)[string];
		const present =
			versions.get(name) ??
			new Map([[entry.current, new Set(entry.dependentPackages.map((one) => one.name))]]);
		if (compare(newest(present.keys()), entry.latest) >= 0) {
			split.push([name, present]);
		} else {
			const who = sorted(new Set([...present.values()].flatMap((one) => Array.from(one))));
			behind.push([name, byVersion(present.keys()).join(', '), entry.latest, who]);
		}
	}
	// A package at two majors that nothing calls out of date: every copy is on its own latest line.
	for (const name of sorted(versions.keys())) {
		const present = versions.get(name) as Map<string, Set<string>>;
		if (!(name in outdated) && new Set([...present.keys()].map(major)).size > 1)
			split.push([name, present]);
	}
	if (names) return behind.map(([name]) => name).filter((name) => !several.has(name));

	const lines: string[] = [];
	if (behind.length) {
		lines.push('Out of date -- the newest the workspace holds is behind the registry:', '');
		const width = Math.max(...behind.map(([name]) => name.length));
		for (const [name, have, latest, who] of behind) {
			lines.push(`  ${name.padEnd(width)}  ${have} -> ${latest}   (${who.join(', ')})`);
		}
	} else {
		lines.push(
			"Nothing is out of date: every package's newest copy here is the registry's latest.",
		);
	}
	let warned = 0;
	for (const [name, present] of split) {
		const copies = byVersion(present.keys()).map(
			(one) => `${one} in ${sorted(present.get(one) as Set<string>).join(', ')}`,
		);
		if (several.has(name)) {
			lines.push(
				'',
				`allowed at several majors: ${name}\n    ${copies.join('\n    ')}\n    because ${several.get(name)}`,
			);
		} else {
			warned += 1;
			lines.push('', `warning: ${name} is held at several majors\n    ${copies.join('\n    ')}`);
		}
	}
	if (warned)
		lines.push(
			'',
			'Move every copy to one major, or allow the pair in versions.toml with the reason.',
		);
	const splitNames = new Set(split.map(([name]) => name));
	for (const name of sorted(several.keys())) {
		if (!splitNames.has(name)) {
			lines.push(
				'',
				`versions.toml allows ${name} at several majors, and the workspace holds one: drop the line.`,
			);
		}
	}
	return lines;
}

/** The task: `outdated [--names]`, from the repository's root. */
export function main(root = process.cwd(), args: readonly string[] = process.argv.slice(2)): void {
	const names = args.includes('--names') || process.env.usage_names === 'true';
	const lines = report(root, names);
	if (lines.length) console.log(lines.join('\n'));
}

if (import.meta.main) main();
