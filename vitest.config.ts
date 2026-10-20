import { defineConfig } from 'vitest/config';

// The scripts' tests alone: every repository below runs its own suite from its own root.
export default defineConfig({
	test: { include: ['scripts/**/*_test.res.mjs'] },
});
