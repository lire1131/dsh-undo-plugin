// Guard: the package.json "version" must be valid semver.
// npm/pnpm refuse to install a package whose version field is not semver
// (e.g. "0.3.3.1" broke `dsh plugin add` / pnpm installs — issue #5).
import { readFileSync } from 'node:fs';

const pkg = JSON.parse(
  readFileSync(new URL('../package.json', import.meta.url), 'utf8'),
);
const SEMVER =
  /^\d+\.\d+\.\d+(?:-[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?(?:\+[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?$/;

if (!SEMVER.test(pkg.version)) {
  console.error(`invalid semver version in package.json: ${pkg.version}`);
  process.exit(1);
}
console.log(`version OK: ${pkg.version}`);
