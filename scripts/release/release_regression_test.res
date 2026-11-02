@module("vitest") external test: (string, unit => unit) => unit = "test"
@module("node:assert/strict") external equal: ('a, 'a) => unit = "deepStrictEqual"

test("renaming columns removes old table heads and preserves legacy artifact rows", () => {
  let columns = ["Driver", "Version", "Commit", "Architecture"]
  let legacy = "| workerd | 1.0.0 | old | x86_64 |"
  let row = "| machine | 2.0.0 | new | aarch64 |"
  let manifest = JSON.parseOrThrow(`{"artifacts":[
		{"name":"driver-machine","version":"2.0.0","row":["machine","2.0.0","new","aarch64"]}
	]}`)
  let old =
    [
      "| Program | Version | Revision | Download |",
      "| :--- | ---: | :---: | --- |",
      legacy,
      "| Runtime | Version | Commit |",
      "| --- | --- | --- |",
      "| machine | 2.0.0 | stale | x86_64 |",
    ]->Array.join("\n")
  let notes = Release.notesOf(manifest, ~body=old, ~columns)
  // Comparing old heads with the new labels used to preserve them as data rows.
  equal(notes, [...Manifest.header(columns), row, legacy]->Array.join("\n"))
  equal(Release.notesOf(manifest, ~body=notes, ~columns), notes)
})

let repair = (~already, ~failedEdit=false) => {
  let root = Node.mkdtempSync(Node.join([Node.tmpdir(), "release-repair-"]))
  let gh = Node.join([root, "gh"])
  let calls = Node.join([root, "calls"])
  let archive = Node.join([root, "machine-1.0.0-linux-x86_64.tar.gz"])
  Node.writeFileSync(archive, "archive")
  Node.writeFileSync(calls, "")
  Node.writeFileSync(
    gh,
    `#!/usr/bin/env node
const fs = require('node:fs');
fs.appendFileSync(${JSON.stringifyAny(
        calls,
      )->Option.getOrThrow}, JSON.stringify(process.argv.slice(2)) + '\\n');
if (${failedEdit
        ? "true"
        : "false"} && process.argv[3] === 'edit' && process.argv[4] === '2000.01.02') process.exit(1);
`,
  )
  equal(Node.run("chmod", ["+x", gh]), 0)
  let script = Node.join([Node.cwd(), "scripts/release/release.res.mjs"])
  let program = `
import assert from 'node:assert/strict';
import fs from 'node:fs';
import {releasing, repaired} from ${JSON.stringifyAny(script)->Option.getOrThrow};
import {day} from ${JSON.stringifyAny(
      Node.join([Node.cwd(), "scripts/release/manifest.res.mjs"]),
    )->Option.getOrThrow};
process.env.PATH = ${JSON.stringifyAny(root)->Option.getOrThrow} + ':' + process.env.PATH;
const tag = day(Date.now());
const archive = ${JSON.stringifyAny(archive)->Option.getOrThrow};
const artifact = {name: 'machine', version: '1.0.0', commit: 'new',
  assets: [{target: 'linux-x86_64', kind: 'binary', path: archive}],
  row: ['machine', '1.0.0', 'new', 'x86_64']};
const standing = (tag, address, files = []) => ({tag_name: tag, draft: false, body: '',
  assets: [...files.map(name => ({name})), {name: 'manifest.json', browser_download_url: address}]});
globalThis.fetch = async url => {
  if (url === 'https://example.com/bad') return new Response('', {status: 503});
  assert.ok(['https://example.com/today', 'https://example.com/good'].includes(url));
  return new Response(JSON.stringify({artifacts: [url.endsWith('/today') ? artifact :
    {name: 'legacy', version: '0.1.0', row: ['legacy', '0.1.0', 'old', 'x86_64']}]}));
};
const releases = [standing('2000.01.01', 'https://example.com/bad'),
  standing('2000.01.02', 'https://example.com/good')];
if (${already
      ? "true"
      : "false"}) releases.unshift(standing(tag, 'https://example.com/today', ['machine-1.0.0-linux-x86_64.tar.gz']));
const result = await releasing([artifact], releases, 'owner/repo',
  ['Driver', 'Version', 'Commit', 'Architecture'], ${JSON.stringifyAny(root)->Option.getOrThrow});
assert.equal(result.TAG, ${failedEdit ? "'Error'" : "'Ok'"});
const calls = fs.readFileSync(${JSON.stringifyAny(
      calls,
    )->Option.getOrThrow}, 'utf8').trim().split('\\n').map(JSON.parse);
assert.equal(calls.filter(args => args[1] === 'edit' && args[2] === '2000.01.01').length, 0);
assert.equal(calls.filter(args => args[1] === 'edit' && args[2] === '2000.01.02').length, 1);
assert.equal(calls.filter(args => args[1] === 'create').length, ${already ? "0" : "1"});
if (${already
      ? "false"
      : "true"}) assert.ok(calls.some(args => args[2] === tag && args.includes('--draft=false')));
`
  let program =
    program ++ `
assert.equal((await repaired([standing('2000.01.01', 'https://example.com/bad')],
  'owner/repo', ['Driver', 'Version', 'Commit', 'Architecture'], [], true)).TAG, 'Error');
`
  let result = Node.spawnSync(
    "node",
    ["--input-type=module", "--eval", program],
    {encoding: "utf8", timeout: 15000},
  )
  equal(result.status->Nullable.getOr(1), 0)
  let warning = result.stderr->Nullable.getOr("")
  equal(warning->String.includes("warning: 2000.01.01, notes not repaired"), true)
  equal(warning->String.includes("answered 503"), true)
  Node.rmSync(root, {recursive: true, force: true})
}

test("an unreadable older manifest warns after publication and other notes are repaired", () => {
  repair(~already=false)
})

test("an unreadable older manifest warns on an already released run", () => {
  repair(~already=true)
})

test("a failed notes edit still fails after an older manifest could not be read", () => {
  repair(~already=true, ~failedEdit=true)
})

test("a day's rows are newest first, the entries of one commit keeping their order", () => {
  let columns = ["Driver", "Version"]
  let entry = (name, version, commit) =>
    `{"name":"${name}","version":"${version}","commit":"${commit}","row":["${name}","${version}"]}`
  let manifest = JSON.parseOrThrow(
    `{"artifacts":[${entry("a", "0.1.3", "x")},${entry("b", "0.1.3", "x")},${entry(
        "a",
        "0.1.4",
        "y",
      )}]}`,
  )
  let notes = Release.notesOf(manifest, ~body="", ~columns)
  equal(
    notes,
    [...Manifest.header(columns), "| a | 0.1.4 |", "| a | 0.1.3 |", "| b | 0.1.3 |"]->Array.join(
      "\n",
    ),
  )
  equal(Release.notesOf(manifest, ~body=notes, ~columns), notes)
})
