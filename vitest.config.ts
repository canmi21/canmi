import { defineConfig } from 'vitest/config';

// The task libraries' tests alone: every repository below runs its own suite from its own root.
export default defineConfig({
	test: { include: ['.mise/tasks/**/*.test.ts', 'scripts/**/*_test.res.mjs'] },
});
