import { defineConfig } from 'vitest/config';

// The workspace's own tests, every repository below running its own suite from its own root.
const quiet = new URL('scripts/bindings/jj-test.toml', import.meta.url).pathname;

export default defineConfig({
	test: {
		// A test's repository signs with no key of the author's, as a key under load fails it.
		env: { JJ_CONFIG: quiet, GIT_CONFIG_GLOBAL: '/dev/null', GIT_CONFIG_SYSTEM: '/dev/null' },
		include: [
			'scripts/**/*_test.res.mjs',
			'model/**/*_test.res.mjs',
			'checks/**/*_test.res.mjs',
			'hooks/**/*_test.res.mjs',
			'.github/**/*_test.res.mjs',
		],
	},
});
