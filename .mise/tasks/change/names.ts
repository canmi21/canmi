/**
 * The gate holding each app's directory to its declaration's `name`: the artifact is named for the
 * directory and the container for `name`, so two names for one app would deploy one and run the
 * other. Each repository whose apps carry a `service.toml` runs it from its `verify`. RFC l6r4u.
 */
import { existsSync, readFileSync } from 'node:fs';
import { join, relative } from 'node:path';
import { parse } from 'smol-toml';
import { appDirectories, type Layout } from './graph.ts';

/** Why each app's declaration does not name it as its directory does, in the order found. */
export function misnamed(layout: Layout): string[] {
	const found: string[] = [];
	for (const [leaf, directory] of appDirectories(layout)) {
		const declaration = join(directory, 'service.toml');
		if (!existsSync(declaration)) continue;
		const where = relative(layout.root, declaration);
		let name: unknown;
		try {
			name = parse(readFileSync(declaration, 'utf8')).name;
		} catch (error) {
			found.push(`${where}: does not parse: ${error instanceof Error ? error.message : error}`);
			continue;
		}
		if (name !== leaf)
			found.push(`${where}: name is ${JSON.stringify(name)}, its directory ${leaf}`);
	}
	return found;
}

/** A repository's `check-names` task: every app named as its directory is, or each that is not. */
export function main(layout: Layout): void {
	const found = misnamed(layout);
	if (found.length) {
		console.error('An app is named as its directory is, in its service.toml:\n');
		for (const one of found) console.error(`  ${one}`);
		process.exit(1);
	}
	console.log(`names OK: every app's service.toml names it as its directory does`);
}
