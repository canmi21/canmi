/** A repository's `lint`: oxlint over what it is given, its warnings failing under `AUDIT`. */
import { exec } from './spawn.ts';

exec('oxlint', [...process.argv.slice(2), ...(process.env.AUDIT ? ['--deny-warnings'] : [])]);
