import { defineConfig } from 'vitest/config';

// The workspace's own tests, every repository below running its own suite from its own root.
export default defineConfig({
	test: {
		include: ['scripts/**/*_test.res.mjs', 'model/**/*_test.res.mjs', 'hooks/**/*_test.res.mjs'],
	},
});
