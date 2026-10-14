import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { afterEach, beforeEach, describe, expect, test } from 'vitest';
import { misnamed } from './names.ts';

let root: string;

/** Files under the temporary root, each path to its text. */
function tree(files: Record<string, string>): void {
	for (const [path, text] of Object.entries(files)) {
		mkdirSync(dirname(join(root, path)), { recursive: true });
		writeFileSync(join(root, path), text);
	}
}

beforeEach(() => {
	root = mkdtempSync(join(tmpdir(), 'names-'));
});
afterEach(() => rmSync(root, { recursive: true, force: true }));

const layout = () => ({ root, packageDirectories: [], appRoots: ['apps/control', 'apps/data'] });

describe('an app', () => {
	test('named as its directory passes, and a directory with no declaration is not an app', () => {
		tree({
			'apps/control/registry/service.toml': 'version = 1\nname = "registry"\n',
			'apps/data/store/README.md': '',
		});
		expect(misnamed(layout())).toEqual([]);
	});

	test('named otherwise, or not named at all, is refused by its path', () => {
		tree({
			'apps/control/deployer/service.toml': 'name = "deploy"\n',
			'apps/data/store/service.toml': 'version = 1\n',
		});
		expect(misnamed(layout())).toEqual([
			'apps/control/deployer/service.toml: name is "deploy", its directory deployer',
			'apps/data/store/service.toml: name is undefined, its directory store',
		]);
	});

	test('whose declaration does not parse is refused too', () => {
		tree({ 'apps/data/store/service.toml': 'name = \n' });
		expect(misnamed(layout())[0]).toMatch(/^apps\/data\/store\/service.toml: does not parse/);
	});
});
