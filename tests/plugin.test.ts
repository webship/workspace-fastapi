import test from 'node:test';
import assert from 'node:assert';
import fs from 'fs';
import path from 'path';
import { spawnSync } from 'child_process';

import { register, assistantContext, PLATFORM, COMMANDS, AGENTS } from '../src/index';

// Compiled, these tests run from dist/tests, so the package root is one folder further up.
const PKG = fs.existsSync(path.join(__dirname, '..', 'package.json')) ? path.join(__dirname, '..') : path.join(__dirname, '..', '..');
const read = (f: string) => fs.readFileSync(path.join(PKG, f), 'utf8');
const manifest = JSON.parse(read('package.json')).workspacePlugin;

test('the manifest names the plugin, and every file it names ships', () => {
  assert.strictEqual(manifest.name, PLATFORM);
  const named = [...manifest.commands.files, ...manifest.scripts.functions, ...manifest.scripts.args, ...manifest.scripts.machine,
    ...manifest.ai.agents, ...manifest.ai.skills, ...manifest.ai.commands, ...manifest.ai.prompts, ...manifest.features];
  for (const f of named) assert.ok(fs.existsSync(path.join(PKG, f)), `${f} is in the package`);
  assert.deepStrictEqual(manifest.commands.files.map((f: string) => path.basename(f)), COMMANDS);
  assert.deepStrictEqual(manifest.ai.agents.map((f: string) => path.basename(f, '.md')), AGENTS);
  assert.deepStrictEqual(manifest.commands.types, ['sites'], 'the commands go to sites folders only');
  const files: string[] = JSON.parse(read('package.json')).files;
  for (const f of named) assert.ok(files.includes(f.split('/')[0]), `${f} is published with the package`);
  assert.match(manifest.featuresSite, /^cmd-fastapi-project\.sh ci-fastapi --install --add-users --runtime docker$/, 'CI builds the template on Docker Compose for the features, with its accounts');
});

test('the builder finds the workspace by itself, names its folder, and sources its args from where the installer puts them', () => {
  for (const f of manifest.commands.files) {
    const src = read(f);
    assert.match(src, /^#!\/usr\/bin\/env bash/, `${f} is a bash script`);
    assert.match(src, /WORKSPACE_SCRIPTS="\$\{WORKSPACE_SCRIPTS:-\$\(cd "\$\(dirname "\$\{BASH_SOURCE\[0\]\}"\)\/\.\.\/core\/scripts" && pwd\)\}"/, `${f} locates the tooling from its own path`);
    assert.match(src, /workspace\.__WORKSPACE__\.settings\.yml/, `${f} loads the settings of the folder it is installed into`);
    assert.match(src, /source \$\{WORKSPACE_SCRIPTS\}\/plugins\/fastapi\/args\/arg-[a-z-]+\.sh \|\| exit 1 ;/, `${f} reads its arguments from the plugin's args`);
    const last = src.trim().split('\n').pop() as string;
    assert.match(read('scripts/functions/fun-fastapi.sh'), new RegExp(`^function ${last.replace(/ ;$/, '')}\\(\\)`, 'm'), `${f} ends by calling a function the plugin defines`);
  }
  assert.match(read('commands/cmd-fastapi-project.sh'), /^# workspace-name: FastAPI/m, 'the builder carries the name the Build list shows');
});

test('every shell script parses', () => {
  for (const f of [...manifest.commands.files, ...manifest.scripts.functions, ...manifest.scripts.args]) {
    const r = spawnSync('bash', ['-n', path.join(PKG, f)], { encoding: 'utf8' });
    assert.strictEqual(r.status, 0, `${f}: ${r.stderr}`);
  }
});

test('the functions carry the names the core\'s tools look for, and build the app\'s own image on its own pinned Postgres', () => {
  const src = read('scripts/functions/fun-fastapi.sh');
  for (const fn of ['set_fastapi_users', 'add_fastapi_users', 'cancel_fastapi_users', 'testing_configure_fastapi', 'fastapi_build',
    'fastapi_is_project', 'fastapi_export_db', 'fastapi_import_db', 'fastapi_db_extension']) {
    assert.match(src, new RegExp(`^function ${fn}\\(\\) \\{`, 'm'), `${fn} is defined`);
  }
  assert.doesNotMatch(src, /^function build_fastapi\(\)/m, 'the core\'s own example function is not redefined');
  assert.match(src, /--project-type=generic --webserver-type=generic --docroot=""/, 'the app\'s own server serves the app');
  assert.match(src, /--omit-containers=db/, 'DDEV\'s db is omitted: the app\'s Postgres is its own');
  assert.match(src, /^readonly FASTAPI_TEMPLATE_VERSION='0\.12\.0';$/m, 'a release of the template');
  assert.match(src, /^readonly FASTAPI_POSTGRES_IMAGE='docker\.io\/library\/postgres@sha256:[0-9a-f]{64}';$/m, 'Postgres pinned by digest');
  assert.match(src, /git clone --quiet --depth 1 --branch "\$\{FASTAPI_TEMPLATE_VERSION\}"/, 'the template is taken at its pinned release');
  assert.match(read('scripts/docker-compose.fastapi.yaml'), /pull_policy: build/, 'the app\'s own image is built, never pulled');
  assert.doesNotMatch(src + read('scripts/docker-compose.fastapi.yaml'), /:latest\b|@latest\b/, 'nothing is taken at latest');
  assert.match(src, /^readonly FASTAPI_STEPS_VERSION='\^2\.0\.\d+';$/m, 'the testing setup takes the pack\'s release line');
  assert.doesNotMatch(src, /ddev stop -y/, 'ddev stop takes no -y');
  // Every tool of the app runs in its container: never python, pip, uv, npm or bun at the start of a line of the host's shell.
  for (const line of src.split('\n')) {
    if (/^\s*(python3? -m pip|pip|uv|npm|npx|bun|fastapi|alembic) /.test(line)) assert.fail(`a tool of the app runs on the host: ${line.trim()}`);
  }
});

test('register() adds the assistant context and nothing else', () => {
  const calls: string[] = [];
  const api: any = { name: 'fastapi', addAssistantContext: (fn: () => string) => calls.push(fn()) };
  register(api);
  assert.strictEqual(calls.length, 1);
  assert.strictEqual(calls[0], assistantContext());
  for (const c of COMMANDS) assert.ok(calls[0].includes(c), `the assistant is told about ${c}`);
  for (const a of AGENTS) assert.ok(calls[0].includes(a), `the assistant is told about ${a}`);
  assert.ok(calls[0].includes('cmd-tools-testing.sh <name>'), 'and how an app gets the step pack');
  assert.ok(calls[0].includes('token address'), 'and what the steps do');
});

test('the docs say container-based, name only what ships, and carry no personal value', () => {
  const docs = ['README.md', ...manifest.ai.agents, 'scripts/functions/fun-fastapi.sh'];
  for (const f of docs) {
    const src = read(f);
    assert.doesNotMatch(src, /DDEV-only/i, `${f}: the workspace is container-based, DDEV by default`);
    assert.doesNotMatch(src, /\/home\/(?!YOUR_USER)[a-z]/, `${f} carries no personal path`);
    const mails = src.match(/[A-Za-z0-9._%+-]+@[A-Za-z0-9-]+\.[a-z]{2,}/g) || [];
    for (const m of mails) assert.match(m, /@example\.(com|org)$/, `${f}: ${m} is not an example address`);
  }
  for (const c of COMMANDS) assert.ok(read('README.md').includes(c), `the README lists ${c}`);
});
