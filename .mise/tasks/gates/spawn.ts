/** A gate's one command, run in the repository with its output as it arrives, ending as it ends. */
import { spawnSync } from 'node:child_process';

/** The words `value` holds, split as an unquoted shell variable is, or none for none. */
export const words = (value: string | undefined): string[] =>
	(value ?? '').split(/\s+/).filter(Boolean);

/** Runs `command` from the repository's root and exits with its status. */
export function exec(command: string, args: readonly string[]): never {
	const ran = spawnSync(command, args, { stdio: 'inherit' });
	if (ran.error) console.error(`${command}: ${ran.error.message}`);
	process.exit(ran.status ?? 1);
}
