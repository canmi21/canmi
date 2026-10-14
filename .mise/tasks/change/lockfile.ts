/**
 * A pnpm lockfile's importers, read as text: each package directory's own section, what it asks for
 * and what that resolved to. Read by ./deployable.ts, so a lockfile change rebuilds only the Node
 * images whose importers, or their packages' importers, moved. RFC l6r4u.
 */

/** Importer path -> its section's lines, every document's section of that path together. */
export function importers(lock: string): Map<string, string> {
	const found = new Map<string, string[]>();
	let inside = false;
	let current: string[] | undefined;
	for (const line of lock.split(/\r?\n/)) {
		if (line === '---' || (line && !line.startsWith(' '))) {
			inside = line === 'importers:';
			current = undefined;
			continue;
		}
		if (!inside) continue;
		// `  path:`, `  'path with spaces':`, or `  path: {}` for an importer that asks for nothing.
		const key = /^ {2}(?:'([^']*)'|([^\s'][^:]*)):(?: (.+))?$/.exec(line);
		if (key) {
			const path = (key[1] ?? key[2]) as string;
			current = found.get(path) ?? [];
			found.set(path, current);
			if (key[3]) current.push(key[3]);
		} else if (current && line.trim()) {
			current.push(line);
		}
	}
	return new Map([...found].map(([path, lines]) => [path, lines.join('\n')]));
}

/** The importer paths whose sections differ between two lockfiles, one absent in either among them. */
export function movedImporters(before: string, after: string): Set<string> {
	const was = importers(before);
	const now = importers(after);
	return new Set(
		[...new Set([...was.keys(), ...now.keys()])].filter((path) => was.get(path) !== now.get(path)),
	);
}
