/**
 * A repository's `lint-rust`: clippy over the crates `verify` names in `RUST_PACKAGES`, or every
 * one, its warnings denied under `AUDIT`.
 */
import { exec, words } from './spawn.ts';

const packages = words(process.env.RUST_PACKAGES);
const denied = process.env.AUDIT ? ['--', '-D', 'warnings'] : [];
exec('cargo', [
	'clippy',
	...(packages.length ? packages : ['--workspace']),
	'--all-targets',
	...denied,
]);
