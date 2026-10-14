/** A repository's `test`: its one vitest suite. */
import { exec } from './spawn.ts';

exec('pnpm', ['exec', 'vitest', 'run']);
