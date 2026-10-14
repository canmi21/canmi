/**
 * One Deploy run's artifact into the bucket, RFC q28g5: `node artifact.ts <name> <dir> [--store]
 * [--hidden] [--dry-run]`, from the workspace's checkout in every repository's CI. Zipped as
 * actions/upload-artifact zipped it, put at `<owner>/<repo>/<run>/<name>.zip`, then `<name>.json`
 * beside it; a `deploy-*` or `worker-*` then prunes the repository's runs.
 *
 * Reached by the S3 API alone, signed here: ARTIFACTS_ENDPOINT, _REGION, _BUCKET, _WRITE_KEY_ID
 * and _WRITE_SECRET, path-style unless ARTIFACTS_VIRTUAL_HOST is `true`. It imports nothing but
 * node's own, since CI runs it with no install.
 */
import { createHash, createHmac } from 'node:crypto';
import {
	closeSync,
	createReadStream,
	openSync,
	readdirSync,
	readSync,
	rmSync,
	statSync,
	writeSync,
} from 'node:fs';
import { request as httpRequest } from 'node:http';
import { request as httpsRequest } from 'node:https';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { crc32, deflateRawSync } from 'node:zlib';

const USAGE = 'usage: artifact.ts <name> <dir> [--store] [--hidden] [--dry-run]';
/** The names a Deploy run's artifacts take. */
const NAME = /^(declarations|deploy-[a-z0-9-]+|worker-[a-z0-9-]+)$/;
/** The runs kept of each pruned artifact, and the repository's runs no sweep touches. */
const KEPT = 2;
/** upload-artifact's default compression level. */
const LEVEL = 6;
const CHUNK = 1 << 20;
const ATTEMPTS = 3;
/** The largest a zip without ZIP64 can say, and the largest one PUT may carry. */
const ZIP_LIMIT = 0xffffffff;

export interface Bucket {
	endpoint: URL;
	region: string;
	bucket: string;
	keyId: string;
	secret: string;
	virtualHost: boolean;
}

export interface Entry {
	/** The path in the zip, `/`-separated. */
	name: string;
	path: string;
}

/** The files under `dir`, sorted, with what a leading dot hides left out unless `hidden`. */
export function files(dir: string, hidden: boolean, prefix = ''): Entry[] {
	const found: Entry[] = [];
	const names = readdirSync(dir).toSorted();
	for (const name of names) {
		if (!hidden && name.startsWith('.')) continue;
		const path = join(dir, name);
		// Followed, as upload-artifact follows a link to what it points at.
		const stats = statSync(path);
		if (stats.isDirectory()) found.push(...files(path, hidden, `${prefix}${name}/`));
		else if (stats.isFile()) found.push({ name: `${prefix}${name}`, path });
	}
	return found;
}

/** A date as a zip's DOS time and date, in local time as archiver writes it. */
function dos(date: Date): [number, number] {
	const time = (date.getHours() << 11) | (date.getMinutes() << 5) | (date.getSeconds() >> 1);
	const day =
		(Math.max(date.getFullYear() - 1980, 0) << 9) | ((date.getMonth() + 1) << 5) | date.getDate();
	return [time, day];
}

/** Calls `each` with every chunk of the file at `path`. */
function chunks(path: string, each: (chunk: Buffer) => void): void {
	const fd = openSync(path, 'r');
	const buffer = Buffer.alloc(CHUNK);
	try {
		for (let read = readSync(fd, buffer); read > 0; read = readSync(fd, buffer)) {
			each(buffer.subarray(0, read));
		}
	} finally {
		closeSync(fd);
	}
}

/**
 * Writes `entries` to a zip at `out`, each deflated or, with `store`, stored, so a large image is
 * streamed rather than held. No ZIP64: an entry or a zip past 4 GiB is refused.
 */
export function zip(entries: Entry[], out: string, store: boolean): void {
	const fd = openSync(out, 'w');
	const central: Buffer[] = [];
	let offset = 0;
	const write = (buffer: Buffer): void => {
		writeSync(fd, buffer);
		offset += buffer.length;
	};
	try {
		for (const entry of entries) {
			const stats = statSync(entry.path);
			if (stats.size > ZIP_LIMIT) throw new Error(`${entry.name} is past what a zip holds`);
			const name = Buffer.from(entry.name, 'utf8');
			// Bit 11, the name is UTF-8, set only where it is not ASCII, as archiver sets it.
			const flags = name.length === entry.name.length ? 0 : 0x0800;
			const [time, day] = dos(stats.mtime);
			let crc = 0;
			let deflated: Buffer | undefined;
			if (store) {
				chunks(entry.path, (chunk) => {
					crc = crc32(chunk, crc);
				});
			} else {
				const whole = Buffer.alloc(stats.size);
				let at = 0;
				chunks(entry.path, (chunk) => {
					chunk.copy(whole, at);
					at += chunk.length;
				});
				crc = crc32(whole);
				deflated = deflateRawSync(whole, { level: LEVEL });
			}
			const method = store ? 0 : 8;
			const size = deflated ? deflated.length : stats.size;
			const at = offset;
			const local = Buffer.alloc(30);
			local.writeUInt32LE(0x04034b50, 0);
			local.writeUInt16LE(20, 4);
			local.writeUInt16LE(flags, 6);
			local.writeUInt16LE(method, 8);
			local.writeUInt16LE(time, 10);
			local.writeUInt16LE(day, 12);
			local.writeUInt32LE(crc >>> 0, 14);
			local.writeUInt32LE(size, 18);
			local.writeUInt32LE(stats.size, 22);
			local.writeUInt16LE(name.length, 26);
			local.writeUInt16LE(0, 28);
			write(local);
			write(name);
			if (deflated) write(deflated);
			else chunks(entry.path, write);
			if (offset > ZIP_LIMIT) throw new Error(`the zip is past 4 GiB at ${entry.name}`);

			const header = Buffer.alloc(46);
			header.writeUInt32LE(0x02014b50, 0);
			// Made by Unix at 4.5, so the mode below is read, as GitHub's own zips say.
			header.writeUInt16LE((3 << 8) | 45, 4);
			header.writeUInt16LE(20, 6);
			header.writeUInt16LE(flags, 8);
			header.writeUInt16LE(method, 10);
			header.writeUInt16LE(time, 12);
			header.writeUInt16LE(day, 14);
			header.writeUInt32LE(crc >>> 0, 16);
			header.writeUInt32LE(size, 20);
			header.writeUInt32LE(stats.size, 24);
			header.writeUInt16LE(name.length, 28);
			// The mode above MS-DOS's archive bit.
			header.writeUInt32LE((((stats.mode & 0xffff) << 16) | 0x20) >>> 0, 38);
			header.writeUInt32LE(at, 42);
			central.push(header, name);
		}
		const start = offset;
		for (const buffer of central) write(buffer);
		const end = Buffer.alloc(22);
		end.writeUInt32LE(0x06054b50, 0);
		end.writeUInt16LE(entries.length, 8);
		end.writeUInt16LE(entries.length, 10);
		end.writeUInt32LE(offset - start, 12);
		end.writeUInt32LE(start, 16);
		write(end);
	} finally {
		closeSync(fd);
	}
}

/** The file's sha256, in hex, and its size. */
export function digest(path: string): { sha256: string; size: number } {
	const hash = createHash('sha256');
	let size = 0;
	chunks(path, (chunk) => {
		hash.update(chunk);
		size += chunk.length;
	});
	return { sha256: hash.digest('hex'), size };
}

function sha256(data: string | Buffer): string {
	return createHash('sha256').update(data).digest('hex');
}

function hmac(key: string | Buffer, data: string): Buffer {
	return createHmac('sha256', key).update(data).digest();
}

/** RFC 3986's unreserved characters left alone, as SigV4 encodes. */
function encode(text: string): string {
	return encodeURIComponent(text).replace(
		/[!'()*]/g,
		(c) => `%${c.charCodeAt(0).toString(16).toUpperCase()}`,
	);
}

export interface Signable {
	method: string;
	/** The path, already encoded, and the query, as sent. */
	path: string;
	query: Record<string, string>;
	/** Every header signed, `host`, `x-amz-date` and `x-amz-content-sha256` among them. */
	headers: Record<string, string>;
}

/** The Authorization header SigV4 gives `signable` for S3 in `region`. */
export function authorization(
	signable: Signable,
	region: string,
	keyId: string,
	secret: string,
): string {
	const headers = Object.entries(signable.headers)
		.map(([name, value]) => [name.toLowerCase(), value.trim()] as const)
		.toSorted(([a], [b]) => (a < b ? -1 : 1));
	const signed = headers.map(([name]) => name).join(';');
	const query = Object.entries(signable.query)
		.map(([key, value]) => `${encode(key)}=${encode(value)}`)
		.toSorted()
		.join('&');
	const canonical = [
		signable.method,
		signable.path,
		query,
		headers.map(([name, value]) => `${name}:${value}\n`).join(''),
		signed,
		signable.headers['x-amz-content-sha256'],
	].join('\n');
	const stamp = signable.headers['x-amz-date'] ?? '';
	const scope = `${stamp.slice(0, 8)}/${region}/s3/aws4_request`;
	const toSign = ['AWS4-HMAC-SHA256', stamp, scope, sha256(canonical)].join('\n');
	let key = hmac(`AWS4${secret}`, stamp.slice(0, 8));
	for (const part of [region, 's3', 'aws4_request']) key = hmac(key, part);
	const signature = createHmac('sha256', key).update(toSign).digest('hex');
	return `AWS4-HMAC-SHA256 Credential=${keyId}/${scope}, SignedHeaders=${signed}, Signature=${signature}`;
}

/**
 * Where `key` is in the bucket, path-style or by virtual host: the Host header, with its port, the
 * name to connect to, and the encoded path.
 */
export function address(bucket: Bucket, key: string): { host: string; name: string; path: string } {
	const encoded = key ? `/${key.split('/').map(encode).join('/')}` : '';
	const { host, hostname } = bucket.endpoint;
	if (bucket.virtualHost) {
		const name = `${bucket.bucket}.${hostname}`;
		return { host: `${bucket.bucket}.${host}`, name, path: encoded || '/' };
	}
	return { host, name: hostname, path: `/${encode(bucket.bucket)}${encoded}` };
}

interface Answer {
	status: number;
	body: string;
}

/** One signed request; `body` a buffer, or a file streamed with its sha256 and size. */
function send(
	bucket: Bucket,
	method: string,
	key: string,
	query: Record<string, string>,
	body?: Buffer | { path: string; sha256: string; size: number },
	type?: string,
): Promise<Answer> {
	const { host, name, path } = address(bucket, key);
	const payload =
		body === undefined ? sha256('') : Buffer.isBuffer(body) ? sha256(body) : body.sha256;
	const stamp = new Date()
		.toISOString()
		.replace(/[-:]/g, '')
		.replace(/\.\d{3}/, '');
	const headers: Record<string, string> = {
		host,
		'x-amz-content-sha256': payload,
		'x-amz-date': stamp,
	};
	const signature = authorization(
		{ method, path, query, headers },
		bucket.region,
		bucket.keyId,
		bucket.secret,
	);
	const length = body === undefined ? 0 : Buffer.isBuffer(body) ? body.length : body.size;
	const search = new URLSearchParams(query).toString();
	const secure = bucket.endpoint.protocol === 'https:';
	return new Promise((resolve, reject) => {
		const sent = (secure ? httpsRequest : httpRequest)(
			{
				method,
				host: name,
				port: bucket.endpoint.port || (secure ? 443 : 80),
				path: search ? `${path}?${search}` : path,
				headers: {
					...headers,
					authorization: signature,
					'content-length': String(length),
					...(type ? { 'content-type': type } : {}),
				},
				timeout: 120_000,
			},
			(response) => {
				const parts: Buffer[] = [];
				response.on('data', (part: Buffer) => parts.push(part));
				response.on('end', () =>
					resolve({
						status: response.statusCode ?? 0,
						body: Buffer.concat(parts).toString('utf8'),
					}),
				);
				response.on('error', reject);
			},
		);
		sent.on('timeout', () => sent.destroy(new Error('no answer within 120 seconds')));
		sent.on('error', reject);
		if (body === undefined) sent.end();
		else if (Buffer.isBuffer(body)) sent.end(body);
		else createReadStream(body.path).on('error', reject).pipe(sent);
	});
}

/** What S3 said went wrong, by its own code and message. */
function refusal(answer: Answer): string {
	const code = /<Code>([^<]*)<\/Code>/.exec(answer.body)?.[1];
	const message = /<Message>([^<]*)<\/Message>/.exec(answer.body)?.[1];
	return `${answer.status}${code ? ` ${code}` : ''}${message ? `: ${message}` : ''}`;
}

/**
 * `send`, tried again on a network error, a 5xx or a 429; anything else not 2xx throws, unless
 * its status is one of `tolerated`, which is answered as it came.
 */
async function attempt(
	tolerated: readonly number[],
	...args: Parameters<typeof send>
): Promise<Answer> {
	const [, method, key] = args;
	for (let tried = 1; ; tried++) {
		let answer: Answer | undefined;
		let why = '';
		try {
			// oxlint-disable-next-line no-await-in-loop -- an attempt follows only the last one's failure
			answer = await send(...args);
		} catch (error) {
			why = error instanceof Error ? error.message : String(error);
		}
		if (answer) {
			if (answer.status >= 200 && answer.status < 300) return answer;
			if (tolerated.includes(answer.status)) return answer;
			why = refusal(answer);
			if (answer.status < 500 && answer.status !== 429) {
				throw new Error(`${method} ${key}: ${why}`);
			}
		}
		if (tried >= ATTEMPTS) throw new Error(`${method} ${key}: ${why}, ${ATTEMPTS} times`);
		console.error(`artifact: ${method} ${key}: ${why}; trying again`);
		// oxlint-disable-next-line no-await-in-loop -- the wait is the point
		await new Promise((resolve) => setTimeout(resolve, 2000 * tried));
	}
}

/** `send`, tried again on a network error, a 5xx or a 429; anything else not 2xx throws. */
function call(...args: Parameters<typeof send>): Promise<Answer> {
	return attempt([], ...args);
}

function unescape(text: string): string {
	return text
		.replace(/&lt;/g, '<')
		.replace(/&gt;/g, '>')
		.replace(/&quot;/g, '"')
		.replace(/&apos;/g, "'")
		.replace(/&amp;/g, '&');
}

/** Every key under `prefix`, across as many pages as ListObjectsV2 gives. */
export async function list(bucket: Bucket, prefix: string): Promise<string[]> {
	const keys: string[] = [];
	let token: string | undefined;
	do {
		const query: Record<string, string> = { 'list-type': '2', prefix };
		if (token) query['continuation-token'] = token;
		// oxlint-disable-next-line no-await-in-loop -- each page needs the last one's cursor
		const { body } = await call(bucket, 'GET', '', query);
		for (const match of body.matchAll(/<Key>([^<]*)<\/Key>/g)) keys.push(unescape(match[1] ?? ''));
		const truncated = /<IsTruncated>true<\/IsTruncated>/.test(body);
		token = truncated
			? unescape(/<NextContinuationToken>([^<]*)<\/NextContinuationToken>/.exec(body)?.[1] ?? '')
			: undefined;
		if (truncated && !token) throw new Error(`listing ${prefix}: truncated with no token`);
	} while (token);
	return keys;
}

/** The answers a store gives a request it does not implement, by status or by S3's code. */
const UNIMPLEMENTED = [400, 405, 501];
const UNIMPLEMENTED_CODES = new Set(['NotImplemented', 'MethodNotAllowed']);

/** The ListObjectVersions marker naming the last entry of a page, the next page's start. */
interface Marker {
	key: string;
	version: string;
}

/**
 * The id of every version and delete marker of exactly `key`, across as many pages as
 * ListObjectVersions gives -- a sibling it shares a prefix with is passed over. None where the
 * store does not implement the listing, as a store that keeps no versions need not.
 */
export async function versions(bucket: Bucket, key: string): Promise<string[]> {
	const ids: string[] = [];
	let marker: Marker | undefined;
	do {
		const query: Record<string, string> = { versions: '', prefix: key };
		if (marker) {
			query['key-marker'] = marker.key;
			query['version-id-marker'] = marker.version;
		}
		// oxlint-disable-next-line no-await-in-loop -- each page needs the last one's markers
		const answer = await attempt(UNIMPLEMENTED, bucket, 'GET', '', query);
		if (answer.status >= 300) {
			const code = /<Code>([^<]*)<\/Code>/.exec(answer.body)?.[1] ?? '';
			if (answer.status === 501 || UNIMPLEMENTED_CODES.has(code)) return [];
			throw new Error(`listing the versions of ${key}: ${refusal(answer)}`);
		}
		const { body } = answer;
		for (const entry of body.matchAll(/<(Version|DeleteMarker)>([\s\S]*?)<\/\1>/g)) {
			const held = unescape(/<Key>([^<]*)<\/Key>/.exec(entry[2] ?? '')?.[1] ?? '');
			const id = /<VersionId>([^<]*)<\/VersionId>/.exec(entry[2] ?? '')?.[1];
			if (held === key && id) ids.push(unescape(id));
		}
		const truncated = /<IsTruncated>true<\/IsTruncated>/.test(body);
		const next = /<NextKeyMarker>([^<]*)<\/NextKeyMarker>/.exec(body)?.[1];
		const version = /<NextVersionIdMarker>([^<]*)<\/NextVersionIdMarker>/.exec(body)?.[1];
		if (truncated && !next) {
			throw new Error(`listing the versions of ${key}: truncated with no marker`);
		}
		marker = truncated
			? { key: unescape(next ?? ''), version: unescape(version ?? '') }
			: undefined;
	} while (marker);
	return ids;
}

/**
 * Deletes `key` as a DELETE always has, then every version and delete marker of it the store still
 * keeps, so the bytes go now. A store may keep versions with S3 Versioning off, answering a DELETE
 * with a marker alone -- repos/infra/spec/architecture/host.md, "The machine pulls; nothing pushes into
 * it". A version already gone is not an error.
 */
export async function erase(bucket: Bucket, key: string): Promise<void> {
	await call(bucket, 'DELETE', key, {});
	for (const version of await versions(bucket, key)) {
		// oxlint-disable-next-line no-await-in-loop -- one key's versions, in the order listed
		await attempt([404], bucket, 'DELETE', key, { versionId: version });
	}
}

/** An artifact's keys with its `.json` first, so a digest never outlives the zip it names. */
function ordered(found: string[]): string[] {
	return found.toSorted((a, b) => (a.endsWith('.json') ? -1 : b.endsWith('.json') ? 1 : 0));
}

/** Run ids, the newest first: by number, since `100` is newer than `99`. */
function descending(runs: string[]): string[] {
	return runs.toSorted((a, b) => Number(b) - Number(a));
}

/**
 * The keys pruning `artifact` deletes from `keys`, every one under `prefix`: its runs older than
 * the newest KEPT holding it, then each run older than the repository's newest KEPT left holding
 * only `declarations`, so a run that changed declarations alone outlives two newer runs.
 */
export function pruned(keys: string[], prefix: string, artifact: string): string[] {
	const runs = new Map<string, Map<string, string[]>>();
	for (const key of keys) {
		const match = /^(\d+)\/([^/]+)\.(zip|json)$/.exec(key.slice(prefix.length));
		if (!key.startsWith(prefix) || !match) continue;
		const [, run = '', name = ''] = match;
		const held = runs.get(run) ?? new Map<string, string[]>();
		held.set(name, [...(held.get(name) ?? []), key]);
		runs.set(run, held);
	}
	const recent = new Set(descending([...runs.keys()]).slice(0, KEPT));
	const doomed: string[] = [];
	const holding = descending([...runs.keys()].filter((run) => runs.get(run)?.has(artifact)));
	for (const run of holding.slice(KEPT)) {
		const held = runs.get(run);
		doomed.push(...ordered(held?.get(artifact) ?? []));
		held?.delete(artifact);
	}
	for (const [run, held] of runs) {
		if (recent.has(run) || held.size !== 1 || !held.has('declarations')) continue;
		doomed.push(...ordered(held.get('declarations') ?? []));
	}
	return doomed;
}

function fail(message: string): never {
	console.error(`artifact: ${message}`);
	process.exit(1);
}

/** The bucket as the environment names it; every missing name refused at once. */
export function configured(env: NodeJS.ProcessEnv): Bucket {
	const names = [
		'ARTIFACTS_ENDPOINT',
		'ARTIFACTS_REGION',
		'ARTIFACTS_BUCKET',
		'ARTIFACTS_WRITE_KEY_ID',
		'ARTIFACTS_WRITE_SECRET',
	];
	const missing = names.filter((name) => !env[name]);
	if (missing.length) throw new Error(`${missing.join(', ')} not set`);
	const endpoint = new URL(env.ARTIFACTS_ENDPOINT ?? '');
	if (endpoint.pathname !== '/' || endpoint.search) {
		throw new Error('ARTIFACTS_ENDPOINT is an origin, with no path');
	}
	return {
		endpoint,
		region: env.ARTIFACTS_REGION ?? '',
		bucket: env.ARTIFACTS_BUCKET ?? '',
		keyId: env.ARTIFACTS_WRITE_KEY_ID ?? '',
		secret: env.ARTIFACTS_WRITE_SECRET ?? '',
		virtualHost: env.ARTIFACTS_VIRTUAL_HOST === 'true',
	};
}

async function main(): Promise<void> {
	const args = process.argv.slice(2);
	const [name, dir, ...rest] = args.filter((arg) => !arg.startsWith('--'));
	const flags = new Set(args.filter((arg) => arg.startsWith('--')));
	const known = new Set(['--store', '--hidden', '--dry-run']);
	if (!name || !dir || rest.length || [...flags].some((flag) => !known.has(flag))) fail(USAGE);
	if (!NAME.test(name)) fail(`${name} is not declarations, deploy-<app>-<arch> or worker-<app>`);
	const repository = process.env.GITHUB_REPOSITORY ?? '';
	const run = process.env.GITHUB_RUN_ID ?? '';
	if (!/^[^/]+\/[^/]+$/.test(repository) || !/^\d+$/.test(run)) {
		fail('GITHUB_REPOSITORY and GITHUB_RUN_ID name the run, and are not set');
	}
	const dry = flags.has('--dry-run');
	let bucket: Bucket | undefined;
	try {
		bucket = configured(process.env);
	} catch (error) {
		if (!dry) fail(error instanceof Error ? error.message : String(error));
	}

	const entries = files(dir, flags.has('--hidden'));
	if (!entries.length) fail(`${dir} has no files to upload`);
	const out = join(process.env.RUNNER_TEMP ?? tmpdir(), `${name}.zip`);
	zip(entries, out, flags.has('--store'));
	const { sha256: hex, size } = digest(out);
	const prefix = `${repository}/`;
	const key = `${prefix}${run}/${name}`;
	const record = JSON.stringify({ sha256: hex, size });
	const prunes = name.startsWith('deploy-') || name.startsWith('worker-');
	console.log(
		`artifact: ${entries.length} file(s) from ${dir}, ${size} bytes zipped, sha256 ${hex}`,
	);
	if (dry || !bucket) {
		console.log(`artifact: would put ${key}.zip, then ${key}.json: ${record}`);
		if (prunes) {
			console.log(
				`artifact: would delete ${name} from runs under ${prefix} older than the newest ${KEPT},` +
					' then the declarations of any run left with nothing else',
			);
		}
		rmSync(out);
		return;
	}
	await call(bucket, 'PUT', `${key}.zip`, {}, { path: out, sha256: hex, size }, 'application/zip');
	rmSync(out);
	await call(bucket, 'PUT', `${key}.json`, {}, Buffer.from(record), 'application/json');
	console.log(`artifact: put ${key}.zip and ${key}.json`);
	if (!prunes) return;
	const doomed = pruned(await list(bucket, prefix), prefix, name);
	for (const gone of doomed) {
		// oxlint-disable-next-line no-await-in-loop -- a digest is deleted before the zip it names
		await erase(bucket, gone);
		console.log(`artifact: deleted ${gone}`);
	}
	if (!doomed.length) console.log(`artifact: nothing under ${prefix} to prune`);
}

if (import.meta.main) {
	main().catch((error: unknown) => fail(error instanceof Error ? error.message : String(error)));
}
