import { describe, expect, test } from 'vitest';
import { importers, movedImporters } from './lockfile.ts';

// Two documents, as pnpm writes them: its own config's importer first, then the repository's.
const LOCK = `lockfileVersion: '9.0'

importers:

  .:
    configDependencies: {}
---
lockfileVersion: '9.0'

importers:

  .:
    devDependencies:
      vitest:
        specifier: ^5.0.3
        version: 5.0.3

  apps/compute/executor:
    dependencies:
      '@monoflake/replay':
        specifier: workspace:*
        version: link:../../../libs/replay

  libs/empty: {}

  'libs/odd name':
    dependencies:
      hono:
        specifier: ^4.0.0
        version: 4.13.12

packages:

  hono@4.13.12:
    resolution: {integrity: sha512-x}
`;

describe('the importers', () => {
	test('are each directory, every document of it together, and nothing past them', () => {
		const found = importers(LOCK);
		expect([...found.keys()]).toEqual([
			'.',
			'apps/compute/executor',
			'libs/empty',
			'libs/odd name',
		]);
		expect(found.get('libs/empty')).toBe('{}');
		expect(found.get('.')).toContain('configDependencies');
		expect(found.get('.')).toContain('vitest');
		expect(found.get('libs/odd name')).not.toContain('resolution');
	});

	test('moved are those whose section differs, and one that comes or goes', () => {
		const bumped = LOCK.replace('version: 4.13.12\n\npackages', 'version: 4.13.13\n\npackages');
		expect(movedImporters(LOCK, bumped)).toEqual(new Set(['libs/odd name']));
		// What the packages section resolves to is not an importer's.
		expect(movedImporters(LOCK, LOCK.replace('sha512-x', 'sha512-y'))).toEqual(new Set());
		const gone = LOCK.replace(/\n {2}apps\/compute\/executor:\n(?: {4}.*\n)+/, '\n');
		expect(movedImporters(LOCK, gone)).toEqual(new Set(['apps/compute/executor']));
	});
});
