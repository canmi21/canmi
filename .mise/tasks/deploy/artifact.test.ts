import { execFileSync } from 'node:child_process';
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { createServer } from 'node:http';
import type { AddressInfo } from 'node:net';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { afterEach, describe, expect, test } from 'vitest';

import {
	address,
	authorization,
	configured,
	digest,
	erase,
	files,
	pruned,
	versions,
	zip,
} from './artifact.ts';
import type { Bucket } from './artifact.ts';

const scratch: string[] = [];

afterEach(() => {
	for (const dir of scratch.splice(0)) rmSync(dir, { recursive: true, force: true });
});

function directory(tree: Record<string, string>): string {
	const dir = mkdtempSync(join(tmpdir(), 'artifact-test-'));
	scratch.push(dir);
	for (const [name, content] of Object.entries(tree)) {
		mkdirSync(join(dir, name, '..'), { recursive: true });
		writeFileSync(join(dir, name), content);
	}
	return dir;
}

const BUCKET: Bucket = {
	endpoint: new URL('http://localhost:9000'),
	region: 'us-east-1',
	bucket: 'builds',
	keyId: 'id',
	secret: 'secret',
	virtualHost: false,
};

describe('signing', () => {
	test("gives the signature of AWS's own example of a signed GET", () => {
		// "Example: GET Object" in Amazon S3's "Signature Calculations for the Authorization Header".
		const signed = authorization(
			{
				method: 'GET',
				path: '/test.txt',
				query: {},
				headers: {
					host: 'examplebucket.s3.amazonaws.com',
					range: 'bytes=0-9',
					'x-amz-content-sha256':
						'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
					'x-amz-date': '20130524T000000Z',
				},
			},
			'us-east-1',
			'AKIAIOSFODNN7EXAMPLE',
			'wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY',
		);
		expect(signed).toBe(
			'AWS4-HMAC-SHA256 Credential=AKIAIOSFODNN7EXAMPLE/20130524/us-east-1/s3/aws4_request, ' +
				'SignedHeaders=host;range;x-amz-content-sha256;x-amz-date, ' +
				'Signature=f0e8bdb87c964420e857bd35b5d6ed310bd44f0170aba48dd91039c6036bdb41',
		);
	});

	test('addresses a key path-style unless the bucket is its own host', () => {
		expect(address(BUCKET, 'o/r/1/declarations.zip')).toEqual({
			host: 'localhost:9000',
			name: 'localhost',
			path: '/builds/o/r/1/declarations.zip',
		});
		expect(address({ ...BUCKET, virtualHost: true }, '')).toEqual({
			host: 'builds.localhost:9000',
			name: 'builds.localhost',
			path: '/',
		});
	});
});

describe('configuration', () => {
	const env = {
		ARTIFACTS_ENDPOINT: 'https://s3.example.com',
		ARTIFACTS_REGION: 'auto',
		ARTIFACTS_BUCKET: 'builds',
		ARTIFACTS_WRITE_KEY_ID: 'id',
		ARTIFACTS_WRITE_SECRET: 'secret',
	};

	test('is read by name, path-style unless asked', () => {
		expect(configured(env).virtualHost).toBe(false);
		expect(configured({ ...env, ARTIFACTS_VIRTUAL_HOST: 'true' }).virtualHost).toBe(true);
	});

	test('names everything missing, and refuses an endpoint with a path', () => {
		expect(() => configured({ ARTIFACTS_REGION: 'auto' })).toThrow(
			'ARTIFACTS_ENDPOINT, ARTIFACTS_BUCKET, ARTIFACTS_WRITE_KEY_ID, ARTIFACTS_WRITE_SECRET not set',
		);
		expect(() => configured({ ...env, ARTIFACTS_ENDPOINT: 'https://s3.example.com/x' })).toThrow(
			'no path',
		);
	});
});

describe('pruning', () => {
	const prefix = 'monoflake/platform/';
	const both = (run: number, name: string): string[] => [
		`${prefix}${run}/${name}.zip`,
		`${prefix}${run}/${name}.json`,
	];

	test('keeps the newest two runs of the artifact, by number, digest before zip', () => {
		const keys = [9, 10, 100].flatMap((run) => both(run, 'deploy-geo-arm64'));
		keys.push(...[9, 10, 100].flatMap((run) => both(run, 'deploy-geo-amd64')));
		expect(pruned(keys, prefix, 'deploy-geo-arm64')).toEqual([
			`${prefix}9/deploy-geo-arm64.json`,
			`${prefix}9/deploy-geo-arm64.zip`,
		]);
	});

	test('takes the declarations of a run left with nothing else', () => {
		const keys = [
			...both(1, 'declarations'),
			...both(1, 'deploy-geo-arm64'),
			...both(2, 'declarations'),
			...both(2, 'deploy-geo-arm64'),
			...both(2, 'deploy-shot-arm64'),
			...both(3, 'declarations'),
			...both(3, 'deploy-geo-arm64'),
			...both(4, 'declarations'),
			...both(4, 'deploy-geo-arm64'),
		];
		expect(pruned(keys, prefix, 'deploy-geo-arm64')).toEqual([
			...both(2, 'deploy-geo-arm64').toReversed(),
			...both(1, 'deploy-geo-arm64').toReversed(),
			...both(1, 'declarations').toReversed(),
		]);
	});

	test('keeps a run that changed declarations alone until two newer runs exist', () => {
		// As infra's run does when a push changes a declaration and builds no image.
		const keys = [
			...both(7, 'declarations'),
			...both(8, 'declarations'),
			...both(8, 'deploy-host-arm64'),
			...both(9, 'declarations'),
		];
		expect(pruned(keys, prefix, 'deploy-host-arm64')).toEqual(both(7, 'declarations').toReversed());
		// Run 9 is among the newest two until a second run after it.
		keys.push(...both(10, 'declarations'), ...both(10, 'deploy-host-arm64'));
		expect(pruned(keys, prefix, 'deploy-host-arm64')).toEqual(both(7, 'declarations').toReversed());
		keys.push(...both(11, 'deploy-host-arm64'));
		expect(pruned(keys, prefix, 'deploy-host-arm64')).toEqual([
			...both(8, 'deploy-host-arm64').toReversed(),
			...both(7, 'declarations').toReversed(),
			...both(8, 'declarations').toReversed(),
			...both(9, 'declarations').toReversed(),
		]);
	});

	test('leaves what is not a run of this repository alone', () => {
		const keys = [
			...[1, 2, 3].flatMap((run) => both(run, 'worker-hook')),
			'monoflake/platform/notes.txt',
			'monoflake/platform/x/worker-hook.zip',
			'monoflake/infra/1/worker-hook.zip',
		];
		expect(pruned(keys, prefix, 'worker-hook')).toEqual(both(1, 'worker-hook').toReversed());
	});
});

function unzip(...args: string[]): string {
	return execFileSync('unzip', args, { encoding: 'utf8' });
}

describe('zipping', () => {
	test('holds the files at its root, hidden ones only when asked', () => {
		const dir = directory({ 'a.toml': 'a', 'assets/.assetsignore': 'x', 'assets/b/c.js': 'c' });
		expect(files(dir, false).map((entry) => entry.name)).toEqual(['a.toml', 'assets/b/c.js']);
		expect(files(dir, true).map((entry) => entry.name)).toEqual([
			'a.toml',
			'assets/.assetsignore',
			'assets/b/c.js',
		]);
	});

	test('deflates, or stores, and unzip reads back every byte', () => {
		const content = 'service = "geo"\n'.repeat(1000);
		const dir = directory({ 'image.tar': content, 'service.toml': 'name = "geo"\n' });
		for (const stored of [false, true]) {
			const out = join(dir, '..', `${stored}.zip`);
			scratch.push(out);
			zip(files(dir, false), out, stored);
			expect(unzip('-tq', out)).toContain('No errors detected');
			expect(unzip('-p', out, 'image.tar')).toBe(content);
			const listed = unzip('-Zv', out);
			expect(listed).toMatch(stored ? /compression method:\s+none \(stored\)/ : /deflated/);
			expect(listed).not.toMatch(stored ? /deflated/ : /none \(stored\)/);
			expect(digest(out).size).toBeGreaterThan(0);
		}
	});
});

interface Asked {
	method: string;
	path: string;
	query: Record<string, string>;
}

/** A fake S3 on a free port, answering each request with `answer` and recording every one. */
async function store(
	answer: (asked: Asked) => { status: number; body?: string },
): Promise<{ bucket: Bucket; asked: Asked[]; close: () => Promise<void> }> {
	const asked: Asked[] = [];
	const server = createServer((request, response) => {
		const url = new URL(request.url ?? '/', 'http://localhost');
		const one = {
			method: request.method ?? '',
			path: url.pathname,
			query: Object.fromEntries(url.searchParams),
		};
		asked.push(one);
		const { status, body = '' } = answer(one);
		response.writeHead(status, { 'content-type': 'application/xml' }).end(body);
	});
	await new Promise<void>((resolve) => server.listen(0, resolve));
	const { port } = server.address() as AddressInfo;
	return {
		bucket: { ...BUCKET, endpoint: new URL(`http://localhost:${port}`) },
		asked,
		close: () => new Promise((resolve) => server.close(() => resolve())),
	};
}

/** A ListObjectVersions page holding `entries`, as `[element, key, versionId]`. */
function page(entries: [string, string, string][], next?: [string, string]): string {
	const listed = entries
		.map(
			([element, key, id]) =>
				`<${element}><Key>${key}</Key><VersionId>${id}</VersionId></${element}>`,
		)
		.join('');
	const more = next
		? `<IsTruncated>true</IsTruncated><NextKeyMarker>${next[0]}</NextKeyMarker>` +
			`<NextVersionIdMarker>${next[1]}</NextVersionIdMarker>`
		: '<IsTruncated>false</IsTruncated>';
	return `<?xml version="1.0" encoding="UTF-8"?><ListVersionsResult>${more}${listed}</ListVersionsResult>`;
}

/** What `asked` deleted, as `key` or `key@version`. */
function deleted(asked: Asked[]): string[] {
	return asked
		.filter((one) => one.method === 'DELETE')
		.map((one) => {
			const key = one.path.replace('/builds/', '');
			return one.query.versionId ? `${key}@${one.query.versionId}` : key;
		});
}

describe('erasing', () => {
	const closing: (() => Promise<void>)[] = [];
	afterEach(async () => {
		await Promise.all(closing.splice(0).map((close) => close()));
	});

	test('deletes the key, then finds no version left of it', async () => {
		const fake = await store((one) => ({
			status: one.method === 'DELETE' ? 204 : 200,
			body: page([]),
		}));
		closing.push(fake.close);
		await erase(fake.bucket, 'o/r/1/deploy-a.zip');
		expect(fake.asked).toEqual([
			{ method: 'DELETE', path: '/builds/o/r/1/deploy-a.zip', query: {} },
			{ method: 'GET', path: '/builds', query: { versions: '', prefix: 'o/r/1/deploy-a.zip' } },
		]);
	});

	test('deletes every version and the marker the DELETE left', async () => {
		const key = 'o/r/1/deploy-a.zip';
		const fake = await store((one) =>
			one.method === 'DELETE'
				? { status: 204 }
				: {
						status: 200,
						body: page([
							['DeleteMarker', key, 'hide'],
							['Version', key, 'v2'],
							['Version', key, 'v1'],
						]),
					},
		);
		closing.push(fake.close);
		await erase(fake.bucket, key);
		expect(deleted(fake.asked)).toEqual([key, `${key}@hide`, `${key}@v2`, `${key}@v1`]);
	});

	test('follows a truncated listing by its key and version markers', async () => {
		const key = 'o/r/1/deploy-a.zip';
		const fake = await store((one) => {
			if (one.method === 'DELETE') return { status: 204 };
			if (!one.query['key-marker']) {
				return {
					status: 200,
					body: page(
						[
							['DeleteMarker', key, 'hide'],
							['Version', key, 'v3'],
						],
						[key, 'v3'],
					),
				};
			}
			return {
				status: 200,
				body: page([
					['Version', key, 'v2'],
					['Version', key, 'v1'],
				]),
			};
		});
		closing.push(fake.close);
		expect(await versions(fake.bucket, key)).toEqual(['hide', 'v3', 'v2', 'v1']);
		expect(fake.asked[1]?.query).toEqual({
			versions: '',
			prefix: key,
			'key-marker': key,
			'version-id-marker': 'v3',
		});
	});

	test('takes a store that does not list versions as keeping none', async () => {
		const fake = await store((one) =>
			one.method === 'DELETE'
				? { status: 204 }
				: { status: 501, body: '<Error><Code>NotImplemented</Code></Error>' },
		);
		closing.push(fake.close);
		await erase(fake.bucket, 'o/r/1/deploy-a.zip');
		// Answered once, never tried again as a 5xx would be.
		expect(fake.asked.map((one) => one.method)).toEqual(['DELETE', 'GET']);
	});

	test('takes a store answering the versions listing with its objects as keeping none', async () => {
		// A store that passes over `versions` lists the key itself, a version of nothing.
		const key = 'o/r/1/deploy-a.zip';
		const fake = await store((one) =>
			one.method === 'DELETE'
				? { status: 204 }
				: {
						status: 200,
						body:
							`<ListBucketResult><Contents><Key>${key}</Key></Contents>` +
							'<IsTruncated>false</IsTruncated></ListBucketResult>',
					},
		);
		closing.push(fake.close);
		expect(await versions(fake.bucket, key)).toEqual([]);
	});

	test('never touches a sibling the key is a prefix of', async () => {
		const fake = await store((one) =>
			one.method === 'DELETE'
				? { status: 204 }
				: {
						status: 200,
						body: page([
							['Version', 'a/b', 'mine'],
							['DeleteMarker', 'a/bc', 'theirs'],
							['Version', 'a/bc', 'theirs-too'],
						]),
					},
		);
		closing.push(fake.close);
		await erase(fake.bucket, 'a/b');
		expect(deleted(fake.asked)).toEqual(['a/b', 'a/b@mine']);
	});

	test('refuses a listing that fails for any other reason', async () => {
		const fake = await store((one) =>
			one.method === 'DELETE'
				? { status: 204 }
				: { status: 403, body: '<Error><Code>AccessDenied</Code></Error>' },
		);
		closing.push(fake.close);
		await expect(erase(fake.bucket, 'a/b')).rejects.toThrow('403 AccessDenied');
	});
});
