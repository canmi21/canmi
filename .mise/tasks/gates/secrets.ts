/**
 * The gate refusing a plaintext secrets file: every file the repository's `.sops.yaml` claims is
 * held to what sops writes, a `sops` block and `ENC[` on every value. Run as a repository's
 * `secrets`, from its root.
 *
 * The failure it prevents is one-way: a secret committed in plaintext is on the remote, in every
 * clone and in the reflog, and rotating it is the only remedy, so this runs first. It also catches
 * the half-broken state of an empty value, which sops leaves bare and mise then refuses.
 */
import { existsSync, readdirSync, readFileSync, statSync } from 'node:fs';
import { join, relative, sep } from 'node:path';

/** `path_regex` entries from `.sops.yaml`, read without a YAML dependency. */
export function guardedPatterns(root: string): RegExp[] {
	const rules = join(root, '.sops.yaml');
	if (!existsSync(rules)) return [];
	return [...readFileSync(rules, 'utf8').matchAll(/path_regex:\s*(\S+)/g)].map(
		(match) => new RegExp(match[1] as string),
	);
}

/** Why `text`, a file sops should have written, is not safe to commit, or undefined if it is. */
export function unencrypted(text: string): string | undefined {
	let data: unknown;
	try {
		data = JSON.parse(text);
	} catch {
		return 'not readable as JSON, so it is neither valid plaintext nor valid sops output';
	}
	if (typeof data !== 'object' || data === null || !('sops' in data)) {
		return 'no sops block: this is plaintext';
	}
	const bare = Object.entries(data)
		.filter(
			([key, value]) => key !== 'sops' && typeof value === 'string' && !value.startsWith('ENC['),
		)
		.map(([key]) => key)
		.toSorted();
	return bare.length ? `values are not encrypted: ${bare.join(', ')}` : undefined;
}

/** Pruned while walking, so a build writing and removing its scratch files is never walked. */
const SKIPPED = new Set(['node_modules', '.jj', '.git', 'target']);

/** Every file under `root` but those under a skipped directory, relative to it. */
function walk(root: string): string[] {
	const found: string[] = [];
	const visit = (directory: string) => {
		for (const entry of readdirSync(directory, { withFileTypes: true })) {
			const path = join(directory, entry.name);
			if (entry.isDirectory()) {
				if (!SKIPPED.has(entry.name)) visit(path);
			} else if (
				entry.isFile() ||
				(entry.isSymbolicLink() && statSync(path, { throwIfNoEntry: false })?.isFile())
			) {
				found.push(relative(root, path).split(sep).join('/'));
			}
		}
	};
	visit(root);
	return found;
}

/** The gate: each guarded file encrypted, or every one that is not, by why. */
export function main(root = process.cwd()): void {
	const patterns = guardedPatterns(root);
	if (!patterns.length) {
		console.log('no .sops.yaml rules to enforce');
		return;
	}
	const problems: string[] = [];
	let checked = 0;
	for (const path of walk(root)) {
		if (!patterns.some((pattern) => pattern.test(path))) continue;
		checked += 1;
		let text: string;
		try {
			text = readFileSync(join(root, path), 'utf8');
		} catch {
			text = '';
		}
		const why = unencrypted(text);
		if (why) problems.push(`${path}: ${why}`);
	}
	if (problems.length) {
		console.error('Plaintext secrets found:\n');
		for (const problem of problems) console.error(`  ${problem}`);
		console.error(
			'\nEncrypt with `sops encrypt -i <file>` before committing. If a real credential was ever ' +
				'written here in plaintext, rotate it -- removing the file does not remove it from history.',
		);
		process.exit(1);
	}
	console.log(`secrets OK: ${checked} file(s) encrypted`);
}

if (import.meta.main) main();
