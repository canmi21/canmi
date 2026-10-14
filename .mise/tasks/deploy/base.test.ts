import { execFileSync } from 'node:child_process';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { afterEach, beforeEach, describe, expect, test } from 'vitest';
import { base, holds, lastBuilt, type Run, Unanswered } from './base.ts';

const BUILT = '1'.repeat(40);
const BEFORE = '2'.repeat(40);
const HEAD = '3'.repeat(40);
const ZERO = '0'.repeat(40);

const answering = (commit: string | undefined) => () => commit;
const unanswered = () => {
	throw new Unanswered('HTTP 403');
};
const always = () => true;

describe('the base a push plans against', () => {
	test('is the last commit built, not its before', () => {
		// The cancelled pending run's commit is BEFORE; the last run that succeeded built BUILT.
		const [chosen, why] = base(answering(BUILT), BEFORE, HEAD, always);
		expect(chosen).toBe(BUILT);
		expect(why).toContain(BUILT);
	});

	test('is everything with no run built', () => {
		expect(base(answering(undefined), BEFORE, HEAD, always)[0]).toBe('');
	});

	test('is everything for a commit HEAD does not descend from', () => {
		const [chosen, why] = base(answering(BUILT), BEFORE, HEAD, () => false);
		expect(chosen).toBe('');
		expect(why).toContain('does not descend');
	});

	test('falls back to before when the API does not answer, and says so', () => {
		const [chosen, why] = base(unanswered, BEFORE, HEAD, always);
		expect(chosen).toBe(BEFORE);
		expect(why).toContain('HTTP 403');
		expect(why).toContain('github.event.before');
		expect(base(unanswered, ZERO, HEAD, always)[0]).toBe('');
		expect(base(unanswered, '', HEAD, always)[0]).toBe('');
	});

	test('is its before for a re-run of the commit built', () => {
		expect(base(answering(HEAD), BEFORE, HEAD, always)[0]).toBe(BEFORE);
	});
});

/** What `lastBuilt` makes of one answer from `gh`, and the arguments it asked with. */
function asked(answer: Partial<ReturnType<Run>>): [string | undefined | Error, readonly string[]] {
	let args: readonly string[] = [];
	const ask: Run = (_command, given) => {
		args = given;
		return { status: 0, stdout: '', stderr: '', ...answer };
	};
	try {
		return [lastBuilt('monoflake/platform', ask), args];
	} catch (error) {
		return [error as Error, args];
	}
}

describe('the last commit built', () => {
	test('is the newest push run on main that succeeded', () => {
		const runs = { workflow_runs: [{ head_sha: BUILT, event: 'push' }] };
		const [answer, args] = asked({ stdout: JSON.stringify(runs) });
		expect(answer).toBe(BUILT);
		const path = args[1] as string;
		expect(path.startsWith('repos/monoflake/platform/actions/workflows/deploy.yml/runs?')).toBe(
			true,
		);
		for (const one of ['branch=main', 'event=push', 'status=success', 'per_page=1']) {
			expect(path).toContain(one);
		}
	});

	test('is none when none succeeded', () => {
		expect(asked({ stdout: '{"total_count": 0, "workflow_runs": []}' })[0]).toBeUndefined();
	});

	test.each([
		{ status: 1, stderr: 'HTTP 403: Resource not accessible by integration\n' },
		{ stdout: 'not json' },
		{ stdout: '{"message": "Not Found"}' },
		{ stdout: '{"workflow_runs": [{}]}' },
		{ status: null, error: new Error('spawnSync gh ENOENT') },
		{ status: null, error: new Error('spawnSync gh ETIMEDOUT') },
	])('is unanswered for %o', (answer) => {
		expect(asked(answer)[0]).toBeInstanceOf(Unanswered);
	});

	test('is unanswered with no repository named', () => {
		expect(() => lastBuilt('')).toThrow(Unanswered);
	});
});

describe('a commit held', () => {
	// Against a real repository: two commits on one line, and one on a line of its own.
	let checkout: string;
	let first: string;
	let aside: string;
	const git = (...args: string[]) =>
		execFileSync('git', ['-c', 'user.name=t', '-c', 'user.email=t@t.invalid', ...args], {
			cwd: checkout,
			encoding: 'utf8',
		}).trim();

	beforeEach(() => {
		checkout = mkdtempSync(join(tmpdir(), 'base-'));
		git('init', '-q', '-b', 'main');
		git('commit', '-q', '--allow-empty', '-m', 'first');
		first = git('rev-parse', 'HEAD');
		git('checkout', '-q', '--orphan', 'aside');
		git('commit', '-q', '--allow-empty', '-m', 'aside');
		aside = git('rev-parse', 'HEAD');
		git('checkout', '-q', 'main');
		git('commit', '-q', '--allow-empty', '-m', 'second');
	});

	afterEach(() => rmSync(checkout, { recursive: true, force: true }));

	test('is one HEAD descends from, its own among them', () => {
		expect(holds(first, checkout)).toBe(true);
		expect(holds(git('rev-parse', 'HEAD'), checkout)).toBe(true);
	});

	test('is not one off its line, or one unknown', () => {
		expect(holds(aside, checkout)).toBe(false);
		expect(holds('4'.repeat(40), checkout)).toBe(false);
	});
});
