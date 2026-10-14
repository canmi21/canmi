import { describe, expect, test } from 'vitest';
import { closures, lockMoved, manifestMoved } from './resolved.ts';

type Locked = [name: string, version: string, source: string | null, dependencies: string[]];

/** A lockfile of `[name, version, source or null, dependency references]`. */
function lock(...packages: Locked[]): string {
	let text = 'version = 4\n';
	for (const [name, version, source, dependencies] of packages) {
		text += `\n[[package]]\nname = "${name}"\nversion = "${version}"\n`;
		if (source) text += `source = "${source}"\nchecksum = "${name}${version}"\n`;
		if (dependencies.length)
			text += `dependencies = [${dependencies.map((one) => `"${one}"`).join(', ')}]\n`;
	}
	return text;
}

// A source as the lockfile spells one; its text is never read.
const REGISTRY = 'registry+crates-io';
const BASE = lock(
	['ledger', '0.0.0', null, ['serde']],
	['probe', '0.0.0', null, ['serde', 'getrandom']],
	['serde', '1.0.0', REGISTRY, []],
	['getrandom', '0.2.0', REGISTRY, ['wasi']],
	['wasi', '0.11.0', REGISTRY, []],
);
const BOTH = new Set(['ledger', 'probe']);

describe('the lockfile', () => {
	test('a new dependency moves the crate that takes it alone', () => {
		const head = lock(
			['ledger', '0.0.0', null, ['serde', 'tokio-postgres']],
			['probe', '0.0.0', null, ['serde', 'getrandom']],
			['serde', '1.0.0', REGISTRY, []],
			['tokio-postgres', '0.7.0', REGISTRY, ['getrandom']],
			['getrandom', '0.2.0', REGISTRY, ['wasi']],
			['wasi', '0.11.0', REGISTRY, []],
		);
		expect(lockMoved(BASE, head, BOTH)).toEqual(new Set(['ledger']));
	});

	test('a shared package at another version moves every crate that reaches it', () => {
		const head = BASE.replace('"wasi"\nversion = "0.11.0"', '"wasi"\nversion = "0.11.1"');
		expect(lockMoved(BASE, head, BOTH)).toEqual(new Set(['probe']));
	});

	test('a reference spelled out beside a second version is the same package', () => {
		const head = lock(
			['ledger', '0.0.0', null, ['serde', 'wasi 0.14.0']],
			['probe', '0.0.0', null, ['serde', 'getrandom']],
			['serde', '1.0.0', REGISTRY, []],
			['getrandom', '0.2.0', REGISTRY, ['wasi 0.11.0']],
			['wasi', '0.11.0', REGISTRY, []],
			['wasi', '0.14.0', REGISTRY, []],
		);
		expect(lockMoved(BASE, head, BOTH)).toEqual(new Set(['ledger']));
	});

	test('a crate the lockfile does not hold has nothing to compare', () => {
		expect(closures(BASE, ['quorum']).get('quorum')).toBeUndefined();
		expect(lockMoved(BASE, BASE, new Set(['quorum']))).toEqual(new Set());
	});
});

const ROOT = `
[workspace]
resolver = "3"
members = ["apps/ledger", "apps/probe"]

[workspace.package]
edition = "2024"

[workspace.dependencies]
serde = "1"

[profile.dev]
opt-level = 0

[profile.container]
inherits = "release"
lto = "fat"
`;

const MEMBERS = new Map<string, Record<string, unknown>>([
	[
		'ledger',
		{
			package: { edition: { workspace: true } },
			dependencies: { serde: { workspace: true } },
		},
	],
	['probe', { package: { edition: '2021' }, dependencies: { serde: '1' } }],
]);

const moved = (head: string) => manifestMoved(ROOT, head, MEMBERS);

describe('the root manifest', () => {
	test('a profile no image is built with moves nothing', () => {
		expect(moved(ROOT.replace('opt-level = 0', 'opt-level = 1'))).toEqual(new Set());
	});

	test('the image profile or one it inherits moves every image', () => {
		expect(moved(ROOT.replace('lto = "fat"', 'lto = "thin"'))).toBeUndefined();
		expect(moved(`${ROOT}\n[profile.release]\ndebug = true\n`)).toBeUndefined();
	});

	test('a workspace dependency moves the crates that inherit it', () => {
		expect(moved(ROOT.replace('serde = "1"', 'serde = "1.0.200"'))).toEqual(new Set(['ledger']));
	});

	test('a workspace package key moves the crates that inherit it', () => {
		expect(moved(ROOT.replace('edition = "2024"', 'edition = "2021"'))).toEqual(
			new Set(['ledger']),
		);
	});

	test('membership moves nothing by itself', () => {
		expect(moved(ROOT.replace('"apps/probe"]', '"apps/probe", "apps/new"]'))).toEqual(new Set());
	});

	test('what cannot be told apart moves every image', () => {
		expect(moved(ROOT.replace('resolver = "3"', 'resolver = "2"'))).toBeUndefined();
		expect(moved(`${ROOT}\n[patch.crates-io]\nserde = { path = "../serde" }\n`)).toBeUndefined();
		expect(moved(`${ROOT}\n[unknown]\nkey = 1\n`)).toBeUndefined();
	});

	test('a patch from a registry or git is left to the lockfile', () => {
		const patch = '\n[patch.crates-io]\nserde = { version = "1.0.201", registry = "mirror" }\n';
		expect(moved(ROOT + patch)).toEqual(new Set());
	});
});
