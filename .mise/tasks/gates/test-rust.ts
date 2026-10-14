/** A repository's `test-rust`: the tests of the crates `verify` names in `RUST_PACKAGES`, or all. */
import { exec, words } from './spawn.ts';

const packages = words(process.env.RUST_PACKAGES);
exec('cargo', ['test', ...(packages.length ? packages : ['--workspace'])]);
