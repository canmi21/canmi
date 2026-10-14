/**
 * The base a push's Deploy run plans against, printed, and nothing to build everything: `node
 * base.ts` in CI, from the repository's checkout. It is the head commit of the last Deploy run on
 * main that a push started and that succeeded, so every change since what was last built is built
 * now. Every repository whose CI deploys runs this one copy.
 *
 * `github.event.before` is not that commit. GitHub keeps one pending run in a concurrency group and
 * cancels the pending one when another push queues, so the next run's `before` is the cancelled
 * run's own commit, and what that commit changed was never built. It is still the base when the API
 * cannot answer, as before; and the whole of it is built when there is no such run, or HEAD does
 * not descend from it. Which base was used, and why, goes to stderr. Reads `GITHUB_REPOSITORY`,
 * `GH_TOKEN` (for `gh`) and `BEFORE`.
 */
import { spawnSync } from 'node:child_process';

const WORKFLOW = 'deploy.yml';
const BRANCH = 'main';
const TIMEOUT_MS = 30_000;

/** The API gave no answer that can be read. */
export class Unanswered extends Error {
	override name = 'Unanswered';
}

/**
 * The newest run of the Deploy workflow on main a push started and that succeeded: a run a
 * schedule or a dispatch started built only what it was asked for, so it marks nothing built.
 */
export function runsPath(repository: string): string {
	const query = `branch=${BRANCH}&event=push&status=success&per_page=1`;
	return `repos/${repository}/actions/workflows/${WORKFLOW}/runs?${query}`;
}

/** How `gh` is run, replaced whole by the tests. */
export type Run = (
	command: string,
	args: readonly string[],
) => { status: number | null; stdout: string; stderr: string; error?: Error };

const run: Run = (command, args) => {
	const ran = spawnSync(command, args, { encoding: 'utf8', timeout: TIMEOUT_MS });
	return {
		status: ran.status,
		stdout: ran.stdout ?? '',
		stderr: ran.stderr ?? '',
		error: ran.error,
	};
};

/** That run's head commit; undefined when there is none. Throws Unanswered when the API does not. */
export function lastBuilt(repository: string, ask: Run = run): string | undefined {
	if (!repository) throw new Unanswered('GITHUB_REPOSITORY is not set');
	const ran = ask('gh', ['api', runsPath(repository)]);
	if (ran.error) throw new Unanswered(ran.error.message);
	if (ran.status !== 0) {
		const said = ran.stderr.trim().split('\n')[0];
		throw new Unanswered(said || `gh exited ${ran.status}`);
	}
	let answer: unknown;
	try {
		answer = JSON.parse(ran.stdout);
	} catch (error) {
		throw new Unanswered(`an answer it cannot read: ${String(error)}`);
	}
	if (typeof answer !== 'object' || answer === null || !('workflow_runs' in answer)) {
		throw new Unanswered('an answer it cannot read: no workflow_runs');
	}
	const runs = answer.workflow_runs;
	// No run at all: null, an empty list or an empty table.
	const none = typeof runs === 'object' && runs !== null && !Object.keys(runs).length;
	if (!runs || none) return undefined;
	if (!Array.isArray(runs))
		throw new Unanswered('an answer it cannot read: workflow_runs is no list');
	const sha = (runs[0] as { head_sha?: unknown } | null)?.head_sha;
	if (typeof sha !== 'string') throw new Unanswered('an answer it cannot read: no head_sha');
	return sha;
}

/** Whether the checkout has `commit` and HEAD descends from it. */
export function holds(commit: string, checkout?: string): boolean {
	const commands = [
		['cat-file', '-e', `${commit}^{commit}`],
		['merge-base', '--is-ancestor', commit, 'HEAD'],
	];
	return commands.every((args) => spawnSync('git', args, { cwd: checkout }).status === 0);
}

/** No commit at all: GitHub's `before` for a branch's first push is forty zeros. */
const isZero = (commit: string) => !commit.replace(/^0+|0+$/g, '');

function fallback(before: string, why: string): [string, string] {
	if (isZero(before))
		return ['', `${why}, and the push names no commit before it: building everything`];
	return [before, `${why}: planning against github.event.before, ${before}`];
}

/**
 * [base, why]: the base to plan against, empty for everything. `asked()` answers the last commit
 * built or throws Unanswered; `descends(commit)` says whether HEAD descends from it.
 */
export function base(
	asked: () => string | undefined,
	before: string,
	head: string,
	descends: (commit: string) => boolean,
): [string, string] {
	let built: string | undefined;
	try {
		built = asked();
	} catch (error) {
		if (!(error instanceof Unanswered)) throw error;
		return fallback(before, `the API did not answer (${error.message})`);
	}
	if (built === undefined) {
		return ['', 'no Deploy run a push started on main has succeeded: building everything'];
	}
	// A run re-run at the commit already built: what its own push changed, as a re-run always built.
	if (built === head) return fallback(before, `the last run built ${built}, which is HEAD`);
	if (!descends(built)) {
		return [
			'',
			`the last run built ${built}, which HEAD does not descend from: building everything`,
		];
	}
	return [
		built,
		`planning against ${built}, the last Deploy run a push started on main to succeed`,
	];
}

function main(): void {
	const head = spawnSync('git', ['rev-parse', 'HEAD'], { encoding: 'utf8' }).stdout.trim();
	const repository = process.env.GITHUB_REPOSITORY ?? '';
	const [chosen, why] = base(
		() => lastBuilt(repository),
		process.env.BEFORE ?? '',
		head,
		(commit) => holds(commit),
	);
	console.error(`deploy-base: ${why}`);
	console.log(chosen);
}

if (import.meta.main) main();
