/** A repository's `test-tasks`: the tests of its own Python tasks, the `*_test.py` beside them. */
import { exec } from './spawn.ts';

exec('python3', [
	'-m',
	'unittest',
	'discover',
	'--start-directory',
	'.mise/tasks',
	'--pattern',
	'*_test.py',
]);
