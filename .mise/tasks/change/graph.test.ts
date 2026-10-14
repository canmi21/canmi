import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { afterEach, beforeEach, describe, expect, test } from 'vitest';
import {
	appDirectories,
	appOf,
	dependents,
	embedded,
	type Layout,
	nodeGraph,
	owner,
} from './graph.ts';

let root: string;

/** Files under the temporary root, each path to its text. */
function tree(files: Record<string, string>): void {
	for (const [path, text] of Object.entries(files)) {
		mkdirSync(dirname(join(root, path)), { recursive: true });
		writeFileSync(join(root, path), text);
	}
}

beforeEach(() => {
	root = mkdtempSync(join(tmpdir(), 'graph-'));
});
afterEach(() => rmSync(root, { recursive: true, force: true }));

const layout = (): Layout => ({
	root,
	packageDirectories: ['apps/*/*', 'libs/*'],
	appRoots: ['apps/data', 'apps/edge'],
});

describe('what a binary carries', () => {
	test("is what its own code includes, never a test's", () => {
		tree({
			'apps/data/store/service.toml': 'name = "store"\n',
			'apps/data/store/schema.sql': '',
			'apps/data/store/fixture.json': '',
			'apps/data/store/src/main.rs':
				'const S: &str = include_str!("../schema.sql");\n#[cfg(test)]\nmod tests;\n' +
				'#[cfg(test)]\npub(crate) mod testing;\n#[cfg(test)]\nmod inline { const F: &str = include_str!("../fixture.json"); }\n',
			// A test module in a file of its own, and one in a directory of its own.
			'apps/data/store/src/tests.rs': 'const D: &str = include_str!("../service.toml");\n',
			'apps/data/store/src/testing/mod.rs': 'mod deeper;\n',
			'apps/data/store/src/testing/deeper.rs':
				'const D: &str = include_str!("../../fixture.json");\n',
			'apps/data/store/tests/api.rs': 'const D: &str = include_str!("../service.toml");\n',
		});
		const carried = embedded(root, new Map([['apps/data/store', 'store']]));
		expect([...carried.keys()]).toEqual(['apps/data/store/schema.sql']);
	});

	test('reads a test module declared beside a file that is not the crate root', () => {
		tree({
			'apps/data/secrets/service.toml': '',
			'apps/data/secrets/src/main.rs': 'mod peers;\n',
			'apps/data/secrets/src/peers.rs':
				'const N: &str = include_str!("../service.toml");\n#[cfg(test)]\nmod tests;\n',
			'apps/data/secrets/src/peers/tests.rs':
				'const D: &str = include_str!("../../service.toml");\n',
		});
		const carried = embedded(root, new Map([['apps/data/secrets', 'secrets']]));
		expect(carried.get('apps/data/secrets/service.toml')).toEqual(new Set(['secrets']));
		tree({ 'apps/data/secrets/src/peers.rs': '#[cfg(test)]\nmod tests;\n' });
		expect(embedded(root, new Map([['apps/data/secrets', 'secrets']])).size).toBe(0);
	});
});

describe('the apps', () => {
	test('are found under each root, and a path is in the one it sits in', () => {
		tree({ 'apps/data/store/x': '', 'apps/edge/gateway/x': '', 'libs/sdk/x': '' });
		expect([...appDirectories(layout()).keys()]).toEqual(['store', 'gateway']);
		expect(appOf(layout(), 'apps/data/store/src/main.rs')).toBe('store');
		expect(appOf(layout(), 'apps/data/README.md')).toBeUndefined();
		expect(appOf(layout(), 'libs/sdk/src/lib.rs')).toBeUndefined();
	});
});

describe('the packages', () => {
	test('are found by their patterns, with edges from what they depend on', () => {
		tree({
			'apps/edge/gateway/package.json': JSON.stringify({
				name: '@m/gateway',
				dependencies: { '@m/sdk': 'workspace:*', hono: '4' },
			}),
			'libs/sdk/package.json': JSON.stringify({ name: '@m/sdk' }),
			'libs/probe/package.json': JSON.stringify({
				name: '@m/probe',
				devDependencies: { '@m/sdk': '*' },
			}),
		});
		const { directories, edges } = nodeGraph(layout());
		expect(directories).toEqual(
			new Map([
				['apps/edge/gateway', '@m/gateway'],
				['libs/probe', '@m/probe'],
				['libs/sdk', '@m/sdk'],
			]),
		);
		expect(dependents(['@m/sdk'], edges)).toEqual(new Set(['@m/sdk', '@m/gateway', '@m/probe']));
		expect(owner('libs/sdk/src/a.ts', directories.keys())).toBe('libs/sdk');
		expect(owner('libs/other/a.ts', directories.keys())).toBeUndefined();
	});
});
