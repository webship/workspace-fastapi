import test from 'node:test';
import assert from 'node:assert';
import fs from 'fs';
import os from 'os';
import path from 'path';
import zlib from 'zlib';
import { spawnSync } from 'child_process';

// Compiled, these tests run from dist/tests, so the package root is one folder further up.
const PKG = fs.existsSync(path.join(__dirname, '..', 'package.json')) ? path.join(__dirname, '..') : path.join(__dirname, '..', '..');
const FUNCTIONS = path.join(PKG, 'scripts', 'functions', 'fun-fastapi.sh');
const STAND_INS = path.join(PKG, 'tests', 'fixtures', 'stand-ins.sh');
const read = (f: string) => fs.readFileSync(path.join(PKG, f), 'utf8');
const tmp = (name: string) => fs.mkdtempSync(path.join(os.tmpdir(), `fastapi-${name}-`));
const DIGEST = 'docker.io/library/postgres@sha256:c699303802144847d238196173655dbbecf7a96aeca1565f2b02eb671a1f0b6b';
const VITE = 'Failed to load resource: the server responded with a status of 404 (Not Found)';

// The cucumber.js webship-js 2.0.19 scaffolds (bin/init-webship.js), as far as the testing hook reads it.
const SCAFFOLD = `module.exports = {
  default: {
    timeout: 30000,
    requireModule: ['tsx/cjs'],
    require: [
      'node_modules/webship-js/tests/step-definitions/**/*.js',          // Webship-js core step definitions.
      'tests/step-definitions/**/*.js',                                  // Your custom step definitions.
    ],
    paths: ['tests/features/**/*.feature'],
    worldParameters: {
      launchUrl: process.env.LAUNCH_URL || 'http://localhost:8080',
      selectors: {
        css: {},
      },
    },
  },
};
`;

/** Run bash with the stand-ins and the plugin's functions sourced; every call of a stand-in is written to LOG. */
function bash(script: string, env: Record<string, string> = {}) {
  const dir = tmp('run');
  const log = path.join(dir, 'calls.log');
  const r = spawnSync('bash', ['-c', `source ${STAND_INS}\nsource ${FUNCTIONS}\n${script}`], { encoding: 'utf8', cwd: env.CWD || dir, env: { ...process.env, LOG: log, ...env } });
  const calls = fs.existsSync(log) ? fs.readFileSync(log, 'utf8') : '';
  return { status: r.status, stdout: r.stdout, stderr: r.stderr, calls, dir };
}

/** A project folder with the testing stack scaffolded, and the tooling folder the installer would have filled. */
function project(kind: 'template' | 'own' | 'drupal', scaffold = SCAFFOLD) {
  const root = tmp('plugin');
  const dir = path.join(root, 'dev', 'app1');
  fs.mkdirSync(path.join(dir, '.ddev'), { recursive: true });
  fs.writeFileSync(path.join(dir, '.ddev', 'config.yaml'), `name: app1\ntype: ${kind === 'drupal' ? 'drupal11' : 'generic'}\n`);
  if (kind !== 'drupal') {
    fs.writeFileSync(path.join(dir, '.ddev', 'config.fastapi.yaml'), '# A FastAPI app in this project.\n');
    fs.mkdirSync(path.join(dir, 'app', 'backend', 'app'), { recursive: true });
    fs.writeFileSync(path.join(dir, 'app', 'backend', 'app', 'main.py'), kind === 'template' ? 'app.frontend("/", directory=FRONTEND_DIR)\n' : 'app = FastAPI()\n');
    if (kind === 'template') {
      fs.mkdirSync(path.join(dir, 'app', 'frontend', 'src', 'routes'), { recursive: true });
      fs.writeFileSync(path.join(dir, 'app', 'frontend', 'src', 'routes', 'login.tsx'), 'export const Route = {};\n');
    }
  }
  fs.writeFileSync(path.join(dir, 'cucumber.js'), scaffold);
  fs.writeFileSync(path.join(dir, 'package.json'), JSON.stringify({ name: 'app1', devDependencies: { 'webship-js': '^2.0.19' } }, null, 2));
  const scripts = path.join(root, 'core', 'scripts');
  fs.mkdirSync(path.join(scripts, 'plugins', 'fastapi'), { recursive: true });
  fs.copyFileSync(path.join(PKG, 'testing', 'site.feature'), path.join(scripts, 'plugins', 'fastapi', 'site.feature'));
  return { root, dir, scripts };
}

/** The cucumber.js of a project as node loads it, with the given environment. */
function loadConfig(file: string, env: Record<string, string> = {}) {
  const r = spawnSync(process.execPath, ['-e', 'process.stdout.write(JSON.stringify(require(process.argv[1])))', file], { encoding: 'utf8', env: { ...process.env, ...env } });
  assert.strictEqual(r.status, 0, r.stderr);
  return JSON.parse(r.stdout);
}

test('the default accounts: the app\'s first superuser and a normal account, with the workspace\'s password', () => {
  const r = bash('set_fastapi_users ; echo "${users[*]}|${user_admin_mail}|${user_admin_role}|${user_user_mail}|${user_user_role}|${user_admin_password}|${user_user_password}"');
  assert.strictEqual(r.stdout.trim(), 'admin user|admin@example.com|superuser|user@example.com|user|dD.123123ddd|dD.123123ddd');
});

test('the testing hook adds the step pack, the accounts, the template\'s one known error by its address, and a first feature, once', () => {
  const p = project('template');
  const run = () => bash(`testing_configure_fastapi ${p.dir}`, { WORKSPACE_SCRIPTS: p.scripts });
  const r = run();
  assert.strictEqual(r.status, 0, r.stderr + r.stdout);
  const pkg = JSON.parse(fs.readFileSync(path.join(p.dir, 'package.json'), 'utf8'));
  assert.strictEqual(pkg.devDependencies['@webship-js/fastapi-steps'], '^2.0.0');
  const src = fs.readFileSync(path.join(p.dir, 'cucumber.js'), 'utf8');
  const core = src.indexOf("'node_modules/webship-js/tests/step-definitions/**/*.js'");
  const pack = src.indexOf("'node_modules/@webship-js/fastapi-steps/tests/step-definitions/*.js',");
  assert.ok(core > 0 && pack > core, 'the pack\'s step definitions after webship-js\'s own');
  assert.match(src, /^ {6}users: \{\n {8}admin: \{ username: process\.env\.FASTAPI_ADMIN_USERNAME \|\| 'admin@example\.com', password: process\.env\.FASTAPI_ADMIN_PASSWORD \|\| 'dD\.123123ddd' \},\n {8}user: \{ username: process\.env\.FASTAPI_USER_USERNAME \|\| 'user@example\.com', password: process\.env\.FASTAPI_USER_PASSWORD \|\| 'dD\.123123ddd' \},\n {6}\},$/m, 'the accounts, indented as the file is');
  // The file is still a module node loads: the accounts, their passwords from the environment, and the one error.
  const config = loadConfig(path.join(p.dir, 'cucumber.js'));
  const wp = config.default.worldParameters;
  assert.deepStrictEqual(wp.users, { admin: { username: 'admin@example.com', password: 'dD.123123ddd' }, user: { username: 'user@example.com', password: 'dD.123123ddd' } });
  assert.strictEqual(loadConfig(path.join(p.dir, 'cucumber.js'), { FASTAPI_ADMIN_PASSWORD: 'another' }).default.worldParameters.users.admin.password, 'another');
  assert.strictEqual(wp.launchUrl, 'http://localhost:8080', 'what was there stays');
  const ignore = new RegExp(wp.javascript.ignore);
  for (const url of ['https://app1.ddev.site/vite.svg', 'http://127.0.0.1:43210/vite.svg', 'http://172.18.0.2:30080/vite.svg']) assert.match(`${VITE} @ ${url}`, ignore);
  for (const other of [`${VITE} @ https://app1.ddev.site/api/v1/items/`, `${VITE} @ https://app1.ddev.site/assets/vite.svg`, `${VITE} @ https://app1.ddev.site/vite.svg?v=2`,
    'Failed to load resource: the server responded with a status of 500 (Internal Server Error) @ https://app1.ddev.site/vite.svg', `${VITE}`]) {
    assert.doesNotMatch(other, ignore, other);
  }
  assert.strictEqual(fs.readFileSync(path.join(p.dir, 'tests', 'features', 'site.feature'), 'utf8'), read('testing/site.feature'));
  // A second run changes nothing.
  const before = [fs.readFileSync(path.join(p.dir, 'cucumber.js'), 'utf8'), fs.readFileSync(path.join(p.dir, 'package.json'), 'utf8')];
  const again = run();
  assert.strictEqual(again.status, 0, again.stderr);
  assert.deepStrictEqual([fs.readFileSync(path.join(p.dir, 'cucumber.js'), 'utf8'), fs.readFileSync(path.join(p.dir, 'package.json'), 'utf8')], before);
  assert.doesNotMatch(again.stdout, /cucumber\.js:|package\.json:|site\.feature/);
});

test('the template\'s error goes into a JavaScript block the configuration already has, or takes the place of an empty ignore', () => {
  const block = SCAFFOLD.replace("      launchUrl:", "      javascript: {\n        mode: 'fail',\n      },\n      launchUrl:");
  let p = project('template', block);
  assert.strictEqual(bash(`testing_configure_fastapi ${p.dir}`, { WORKSPACE_SCRIPTS: p.scripts }).status, 0);
  let js = loadConfig(path.join(p.dir, 'cucumber.js')).default.worldParameters.javascript;
  assert.strictEqual(js.mode, 'fail', 'the error mode stays');
  assert.match(`${VITE} @ https://app1.ddev.site/vite.svg`, new RegExp(js.ignore));
  p = project('template', block.replace("        mode: 'fail',", "        mode: 'fail',\n        ignore: '',"));
  assert.strictEqual(bash(`testing_configure_fastapi ${p.dir}`, { WORKSPACE_SCRIPTS: p.scripts }).status, 0);
  js = loadConfig(path.join(p.dir, 'cucumber.js')).default.worldParameters.javascript;
  assert.match(`${VITE} @ https://app1.ddev.site/vite.svg`, new RegExp(js.ignore));
  assert.strictEqual((fs.readFileSync(path.join(p.dir, 'cucumber.js'), 'utf8').match(/ignore:/g) || []).length, 1, 'one ignore');
});

test('an app of your own gets the step pack and the accounts, and no first feature and no allowed error: it has its own pages', () => {
  const p = project('own');
  const r = bash(`testing_configure_fastapi ${p.dir}`, { WORKSPACE_SCRIPTS: p.scripts });
  assert.strictEqual(r.status, 0, r.stderr + r.stdout);
  const config = loadConfig(path.join(p.dir, 'cucumber.js'));
  assert.ok(config.default.require.includes('node_modules/@webship-js/fastapi-steps/tests/step-definitions/*.js'));
  assert.ok(config.default.worldParameters.users.user);
  assert.strictEqual(config.default.worldParameters.javascript, undefined, 'every browser error still counts');
  assert.ok(!fs.existsSync(path.join(p.dir, 'tests', 'features', 'site.feature')));
  assert.match(r.stdout, /the app is not the full-stack template, so no first feature is written/);
});

test('the testing hook waits for the testing stack, and leaves any other project alone', () => {
  const p = project('template');
  fs.rmSync(path.join(p.dir, 'cucumber.js'));
  const r = bash(`testing_configure_fastapi ${p.dir}`, { WORKSPACE_SCRIPTS: p.scripts });
  assert.strictEqual(r.status, 1);
  assert.match(r.stdout, /cucumber\.js is not here yet — run the testing setup again once webship-js is scaffolded/);
  const d = project('drupal');
  const before = fs.readFileSync(path.join(d.dir, 'cucumber.js'), 'utf8') + fs.readFileSync(path.join(d.dir, 'package.json'), 'utf8');
  const other = bash(`testing_configure_fastapi ${d.dir}`, { WORKSPACE_SCRIPTS: d.scripts });
  assert.strictEqual(other.status, 0);
  assert.strictEqual(other.stdout, '');
  assert.strictEqual(fs.readFileSync(path.join(d.dir, 'cucumber.js'), 'utf8') + fs.readFileSync(path.join(d.dir, 'package.json'), 'utf8'), before);
});

test('the app\'s settings: a secret and a database password of the project\'s own, kept by a later build, that only you can read', () => {
  const root = tmp('env');
  const own = path.join(root, '.webship-fastapi');
  assert.strictEqual(bash(`fastapi_write_env ${root} https://app1.ddev.site`).status, 0);
  const env = fs.readFileSync(path.join(own, 'env'), 'utf8');
  const pg = fs.readFileSync(path.join(own, 'postgres.env'), 'utf8');
  const secret = (/^SECRET_KEY=([A-Za-z0-9_-]{40,})$/m.exec(env) || [])[1];
  const dbpass = (/^POSTGRES_PASSWORD=([A-Za-z0-9_-]{20,})$/m.exec(pg) || [])[1];
  assert.ok(secret && dbpass, 'a secret key and a database password');
  assert.ok(env.includes(`\nDATABASE_URL=postgresql://postgres:${dbpass}@postgres:5432/app\n`), 'the app reaches its own Postgres');
  assert.match(pg, /^POSTGRES_DB=app$/m);
  for (const line of [/^FIRST_SUPERUSER=admin@example\.com$/m, /^FIRST_SUPERUSER_PASSWORD=dD\.123123ddd$/m, /^FRONTEND_HOST=https:\/\/app1\.ddev\.site$/m, /^SMTP_HOST=web$/m, /^SMTP_PORT=1025$/m, /^SMTP_TLS=false$/m]) assert.match(env, line);
  assert.doesNotMatch(env + pg, /changethis/);
  assert.strictEqual(fs.statSync(own).mode & 0o777, 0o700);
  for (const f of ['env', 'postgres.env']) assert.strictEqual(fs.statSync(path.join(own, f)).mode & 0o777, 0o600, f);
  // A later build keeps them, at the address and with the mail service of its runtime.
  assert.strictEqual(bash(`runtime_of() { echo docker ; } ; fastapi_write_env ${root} http://127.0.0.1:43210`).status, 0);
  const again = fs.readFileSync(path.join(own, 'env'), 'utf8');
  assert.ok(again.includes(`\nSECRET_KEY=${secret}\n`) && again.includes(`:${dbpass}@postgres:5432/app\n`), 'the same secret and password');
  assert.match(again, /^FRONTEND_HOST=http:\/\/127\.0\.0\.1:43210$/m);
  assert.match(again, /^SMTP_HOST=mail$/m);
  // Another project has its own.
  const other = tmp('env');
  bash(`fastapi_write_env ${other} https://app2.ddev.site`);
  assert.ok(!fs.readFileSync(path.join(other, '.webship-fastapi', 'env'), 'utf8').includes(secret));
});

test('on DDEV: the app\'s service and Postgres\'s from the plugin\'s compose file, Postgres pinned by digest, and the builder\'s mark', () => {
  const root = tmp('ddev');
  const scripts = path.join(root, 'scripts');
  fs.mkdirSync(path.join(scripts, 'plugins', 'fastapi'), { recursive: true });
  const missing = bash(`fastapi_write_ddev_config ${root}/p 'x'`, { WORKSPACE_SCRIPTS: scripts });
  assert.strictEqual(missing.status, 1);
  assert.match(missing.stdout, /docker-compose\.fastapi\.yaml is not in .*: install the plugin \(plugins\.sh --install fastapi\)\./);
  fs.copyFileSync(path.join(PKG, 'scripts', 'docker-compose.fastapi.yaml'), path.join(scripts, 'plugins', 'fastapi', 'docker-compose.fastapi.yaml'));
  const r = bash(`fastapi_write_ddev_config ${root}/p 'the official full-stack FastAPI template 0.12.0'`, { WORKSPACE_SCRIPTS: scripts });
  assert.strictEqual(r.status, 0, r.stderr + r.stdout);
  const ddev = path.join(root, 'p', '.ddev');
  assert.strictEqual(fs.readFileSync(path.join(ddev, 'docker-compose.fastapi.yaml'), 'utf8'), read('scripts/docker-compose.fastapi.yaml'));
  assert.strictEqual(fs.readFileSync(path.join(ddev, '.env'), 'utf8'), `FASTAPI_POSTGRES_IMAGE=${DIGEST}\nFASTAPI_WORKERS=2\n`);
  assert.match(fs.readFileSync(path.join(ddev, 'config.fastapi.yaml'), 'utf8'), /^# app: the official full-stack FastAPI template 0\.12\.0$/m);
});

test('the compose file: the app built from its own Dockerfile, named by no registry, the address sent to it, Postgres healthy first with its data in the project\'s volume', () => {
  const y = read('scripts/docker-compose.fastapi.yaml');
  assert.match(y, /^ {2}postgres:\n {4}image: "\$\{FASTAPI_POSTGRES_IMAGE\}"$/m);
  assert.match(y, /test: \["CMD-SHELL", "pg_isready -U postgres -d app"\]/);
  assert.match(y, /^ {6}- postgres:\/var\/lib\/postgresql$/m);
  assert.match(y, /^volumes:\n {2}postgres:\n?$/m, 'a volume of the project\'s own, removed with it');
  assert.match(y, /^ {4}build:\n {6}context: \$\{DDEV_APPROOT\}\/app\n {6}dockerfile: backend\/Dockerfile$/m);
  assert.doesNotMatch(y.slice(y.indexOf('\n  fastapi:')), /^ {4}image:/m, 'the app\'s image takes no name a pull would ask a registry for');
  assert.match(y, /depends_on:\n {6}postgres:\n {8}condition: service_healthy/);
  assert.match(y, /- \$\{DDEV_APPROOT\}\/\.webship-fastapi\/env$/m);
  assert.match(y, /- \$\{DDEV_APPROOT\}\/\.webship-fastapi\/postgres\.env$/m);
  assert.ok(y.includes('command: ["bash", "-c", "cd /app/backend && bash scripts/prestart.sh && exec fastapi run --workers ${FASTAPI_WORKERS:-2} --port 8000"]'));
  assert.match(y, /VIRTUAL_HOST: \$\{DDEV_HOSTNAME\}\n {6}HTTP_EXPOSE: "80:8000"\n {6}HTTPS_EXPOSE: "443:8000"/);
  assert.match(y, /- HTTP_EXPOSE=8093:80,8025:8025\n {6}- HTTPS_EXPOSE=8457:80,8026:8025/, 'the web container leaves 80 and 443 to the app, and keeps the mail catcher');
});

/** The core's runtime layer, as far as the builder asks it. */
const layer = (rt: string, url: string) => [
  `runtime_of() { echo ${rt} ; }`,
  `rt_url() { echo ${url} ; }`,
  'rt_is_platform() { [ "$2" = fastapi ] ; }',
  'rt_claim() { echo "rt_claim $*" >> "${LOG}" ; }',
  'rt_stack() { echo "rt_stack $*" >> "${LOG}" ; }',
  'rt_service() { echo "rt_service $*" >> "${LOG}" ; }',
  'rt_serve() { echo "rt_serve $1" >> "${LOG}" ; printf "%s\\n" "$2" > "${LOG%/*}/serve.txt" ; }',
].join('\n');

/** A build of app1 in a fresh workspace folder with the stand-ins; `layer` stands for the core's runtime layer. */
function build(opts: { layer?: string; env?: Record<string, string> } = {}) {
  const root = tmp('build');
  fs.mkdirSync(path.join(root, 'dev'), { recursive: true });
  const scripts = path.join(root, 'core', 'scripts');
  fs.mkdirSync(path.join(scripts, 'plugins', 'fastapi'), { recursive: true });
  fs.copyFileSync(path.join(PKG, 'scripts', 'docker-compose.fastapi.yaml'), path.join(scripts, 'plugins', 'fastapi', 'docker-compose.fastapi.yaml'));
  const r = bash(`${opts.layer || ''}\nPROJECT_NAME=\${NAME:-app1}\nfastapi_build`, { WORKSPACE_ROOT: root, WORKSPACE_SCRIPTS: scripts, doc_name: 'dev', RUNTIME: '_none_', INSTALL: 'yes', ADD_USERS: 'yes', LAUNCH: '', ...(opts.env || {}) });
  const serve = path.join(path.dirname(r.dir), path.basename(r.dir), 'serve.txt');
  return { ...r, root, project: path.join(root, 'dev', 'app1'), serve: fs.existsSync(serve) ? fs.readFileSync(serve, 'utf8') : '' };
}

test('a new app on DDEV: the template at its release, its own image and Postgres as services, started, checked, and its accounts made through its API', () => {
  const b = build();
  assert.strictEqual(b.status, 0, b.stderr + b.stdout);
  assert.match(b.calls, /^git clone --quiet --depth 1 --branch 0\.12\.0 https:\/\/github\.com\/fastapi\/full-stack-fastapi-template\.git .*\/dev\/app1\/app$/m);
  assert.ok(!fs.existsSync(path.join(b.project, 'app', '.git')), 'the app is the project\'s, not a clone');
  assert.match(b.calls, /^ddev config --project-type=generic --webserver-type=generic --docroot= --project-name=app1 --omit-containers=db --auto$/m);
  assert.ok(fs.existsSync(path.join(b.project, '.ddev', 'docker-compose.fastapi.yaml')));
  assert.match(fs.readFileSync(path.join(b.project, '.webship-fastapi', 'env'), 'utf8'), /^FRONTEND_HOST=https:\/\/app1\.ddev\.site$/m);
  assert.match(b.calls, /^ddev start -y$/m);
  assert.match(b.calls, /^ddev exec curl -fsS -o \/dev\/null http:\/\/fastapi:8000\/api\/v1\/utils\/health-check\/$/m);
  const order = ['drop_database', 'git clone', 'ddev config', 'ddev start -y', 'health-check', 'ddev exec -s fastapi -d / python3 -c'].map((s) => b.calls.indexOf(s));
  assert.ok(order.every((i) => i >= 0), b.calls);
  assert.deepStrictEqual([...order].sort((x, y) => x - y), order, 'in order');
  assert.match(b.stdout, /User mail: user@example\.com[\s\S]*made\./);
  assert.match(b.stdout, /^dev app1 is served: the FastAPI app in app\/ \(the official full-stack FastAPI template 0\.12\.0\), on Postgres 18\.$/m);
  assert.match(b.stdout, /^Go to https:\/\/app1\.ddev\.site$/m);
  assert.doesNotMatch(b.calls, /^(docker|podman) /m, 'DDEV builds the app\'s image from the compose file');
  assert.doesNotMatch(b.calls, /^ddev stop/m);
});

test('an account that is there already is said so; without --install the project is only made, and the next step said', () => {
  const there = build({ env: { USERS_ANSWER: '400' } });
  assert.strictEqual(there.status, 0, there.stderr + there.stdout);
  assert.match(there.stdout, /there already\./);
  const refused = build({ env: { USERS_ANSWER: '422' } });
  assert.strictEqual(refused.status, 1, 'an account the app refuses fails the build');
  assert.match(refused.stdout, /not made: 422/);
  const b = build({ env: { INSTALL: '', ADD_USERS: '' } });
  assert.strictEqual(b.status, 0, b.stderr + b.stdout);
  assert.doesNotMatch(b.calls, /^ddev start|health-check|python3 -c/m, 'nothing is started');
  assert.match(b.stdout, /^dev app1 is ready: the FastAPI app in app\/ \(the official full-stack FastAPI template 0\.12\.0\)\.$/m);
  assert.match(b.stdout, /Serve it with: cd app1 && ddev start/);
});

test('an app of your own: its repository at its branch, the folder given, laid out as the template is, or the build stops with a message', () => {
  const b = build({ env: { SOURCE: 'https://example.com/apps.git', REF: 'main', APP_PATH: 'services/api', APP_DIR: 'services/api', ADD_USERS: '' } });
  assert.strictEqual(b.status, 0, b.stderr + b.stdout);
  assert.match(b.calls, /^git clone --quiet --depth 1 --branch main https:\/\/example\.com\/apps\.git \/.*\/source$/m);
  assert.ok(fs.existsSync(path.join(b.project, 'app', 'backend', 'Dockerfile')), 'the folder of the app is the project\'s app');
  assert.match(fs.readFileSync(path.join(b.project, '.ddev', 'config.fastapi.yaml'), 'utf8'), /^# app: https:\/\/example\.com\/apps\.git \(main\), services\/api\/$/m);
  const other = build({ env: { SOURCE: 'https://example.com/other.git', LAYOUT: 'none' } });
  assert.strictEqual(other.status, 1);
  assert.match(other.stdout, /https:\/\/example\.com\/other\.git is not laid out as the full-stack template is \(backend\/Dockerfile, backend\/scripts\/prestart\.sh\)/);
  assert.doesNotMatch(other.calls, /^ddev /m, 'no project is configured');
  const gone = build({ env: { SOURCE: 'https://example.com/gone.git', FAIL: 'clone' } });
  assert.strictEqual(gone.status, 1);
  assert.match(gone.stdout, /The app could not be cloned from https:\/\/example\.com\/gone\.git\./);
});

test('--path without --source, a path out of the repository, a quote, a bad project name or an unproven runtime stop the build before anything is made', () => {
  for (const [env, layerOf, message] of [
    [{ APP_PATH: 'api' }, '', /--path names a folder of the repository given with --source: give --source too\. Nothing was changed\./],
    [{ SOURCE: 'https://example.com/app.git', APP_PATH: '../etc' }, '', /--source, --ref and --path take a repository, a branch or tag, and a folder inside the repository/],
    [{ SOURCE: 'https://example.com/app.git', APP_PATH: '/etc' }, '', /take a repository, a branch or tag, and a folder inside the repository/],
    [{ SOURCE: "https://example.com/app.git'; rm -rf /" }, '', /take a repository, a branch or tag, and a folder inside the repository/],
    [{ NAME: 'App_1' }, '', /The project name App_1 must be small letters, digits and dashes/],
    [{ RUNTIME: 'docker' }, '', /--runtime docker needs a Webship Workspace with the container runtimes \(webship\/workspace#694\)/],
    [{}, layer('lando', 'http://127.0.0.1:43212'), /builds on DDEV, Docker Compose, Podman and Kubernetes for now \(--runtime ddev, docker, podman or kubernetes\), not on lando/],
    [{}, 'runtime_of() { echo docker ; }', /FastAPI on docker needs a Webship Workspace whose runtimes take an application's own image and services/],
    [{}, 'unset -f export_project_db', /it needs Webship Workspace 1\.0\.42 or newer \(webship\/workspace#937\)\. Update the workspace\. Nothing was changed\./],
  ] as Array<[Record<string, string>, string, RegExp]>) {
    const b = build({ env, layer: layerOf });
    assert.strictEqual(b.status, 1, JSON.stringify(env) + b.stdout);
    assert.match(b.stdout, message);
    assert.strictEqual(b.calls, '', `nothing ran: ${JSON.stringify(env)}`);
    assert.ok(!fs.existsSync(b.project), 'no project folder was made');
  }
});

for (const [rt, url, engine] of [['docker', 'http://127.0.0.1:43210', 'docker'], ['podman', 'http://127.0.0.1:43211', 'podman'], ['kubernetes', 'http://172.18.0.2:30080', 'docker']]) {
  test(`on ${rt}: the app's own image as the stack, Postgres pinned as a service of the project, the app's server; never a ddev.site`, () => {
    const b = build({ layer: layer(rt, url), env: { RUNTIME: rt } });
    assert.strictEqual(b.status, 0, b.stderr + b.stdout);
    assert.match(b.calls, new RegExp(`^${engine} build -t fastapi-app1:app -f backend/Dockerfile \\.$`, 'm'));
    assert.match(b.calls, /^rt_claim fastapi$/m);
    assert.match(b.calls, /^rt_stack image fastapi-app1:app$/m);
    assert.ok(b.calls.includes(`\nrt_service postgres ${DIGEST} --port 5432 --env-file .webship-fastapi/postgres.env --volume /var/lib/postgresql\n`), b.calls);
    assert.match(b.calls, /^rt_serve 8000$/m);
    assert.match(b.serve, /^set -a && \. \/var\/www\/html\/\.webship-fastapi\/env && set \+a && until python3 -c .*"postgres", 5432.* && cd \/app\/backend && bash scripts\/prestart\.sh && exec fastapi run --workers 2 --port 8000$/m);
    const order = ['ddev config', `${engine} build`, 'rt_claim', 'rt_stack', 'rt_service', 'rt_serve', 'ddev start -y'].map((s) => b.calls.indexOf(s));
    assert.deepStrictEqual([...order].sort((x, y) => x - y), order, 'the image before the stack that takes it');
    const env = fs.readFileSync(path.join(b.project, '.webship-fastapi', 'env'), 'utf8');
    assert.ok(env.includes(`\nFRONTEND_HOST=${url}\n`) && env.includes('\nSMTP_HOST=mail\n'), env);
    assert.ok(fs.existsSync(path.join(b.project, '.webship-fastapi', 'postgres.env')), 'Postgres\'s settings are there before its service is written');
    assert.match(b.calls, /^ddev exec curl -fsS -o \/dev\/null http:\/\/127\.0\.0\.1:8000\/api\/v1\/utils\/health-check\/$/m);
    assert.match(b.calls, /^ddev exec -s web -d \/ python3 -c/m, 'the accounts are made from the web container');
    assert.ok(!fs.existsSync(path.join(b.project, '.ddev', 'docker-compose.fastapi.yaml')), 'no DDEV file');
    assert.match(b.stdout, new RegExp(`^Go to ${url.replace(/[.:/]/g, '\\$&')}$`, 'm'));
    assert.doesNotMatch(b.stdout, /ddev\.site/);
  });
}

test('a project of the builder is known by DDEV\'s file, else by the core\'s rt_is_platform', () => {
  const p = project('template');
  assert.strictEqual(bash(`fastapi_is_project ${p.dir}`).status, 0);
  fs.rmSync(path.join(p.dir, '.ddev', 'config.fastapi.yaml'));
  assert.strictEqual(bash(`fastapi_is_project ${p.dir}`).status, 1);
  assert.strictEqual(bash(`rt_is_platform() { [ "$1" = ${p.dir} ] && [ "$2" = fastapi ] ; } ; fastapi_is_project ${p.dir}`).status, 0);
});

test('the accounts are kept from signing in through the app\'s API, never the first superuser', () => {
  const b = build({ env: { INSTALL: '', ADD_USERS: '' } });
  const r = bash('set_fastapi_users ; PROJECT_NAME=app1 ; cancel_fastapi_users', { WORKSPACE_ROOT: b.root, doc_name: 'dev' });
  assert.strictEqual(r.status, 0, r.stderr + r.stdout);
  assert.match(r.stdout, /user@example\.com: made inactive\./);
  assert.doesNotMatch(r.stdout, /admin@example\.com/);
  assert.match(r.calls, /python3 -c/);
});

test('Backup: pg_dump\'s custom format, checked; a gzipped SQL dump for a .sql.gz, checked to its end; a dump that fails leaves no file', () => {
  const dir = tmp('dump');
  let r = bash(`fastapi_export_db ${dir}/a.dump`, { CWD: dir });
  assert.strictEqual(r.status, 0, r.stderr);
  assert.strictEqual(fs.readFileSync(path.join(dir, 'a.dump'), 'latin1').slice(0, 5), 'PGDMP');
  assert.match(r.calls, /^ddev exec -s postgres -d \/ pg_dump -U postgres -Fc --no-owner --no-privileges app$/m);
  assert.match(r.stdout, new RegExp(`The database of ${path.basename(dir)} \\(Postgres 18, app\\) is in ${dir}/a\\.dump\\.`));
  r = bash(`fastapi_export_db ${dir}/b.sql.gz`, { CWD: dir });
  assert.strictEqual(r.status, 0, r.stderr);
  assert.match(zlib.gunzipSync(fs.readFileSync(path.join(dir, 'b.sql.gz'))).toString(), /PostgreSQL database dump complete/);
  assert.match(r.calls, /^ddev exec -s postgres -d \/ pg_dump -U postgres --no-owner --no-privileges app$/m);
  for (const [file, fail] of [['c.dump', 'dump'], ['d.sql.gz', 'short']]) {
    r = bash(`fastapi_export_db ${dir}/${file}`, { CWD: dir, FAIL: fail });
    assert.strictEqual(r.status, 1, fail);
    assert.ok(!fs.existsSync(path.join(dir, file)), `no ${file} is left for a restore to take`);
    assert.match(r.stderr, new RegExp(`could not be dumped to ${file.replace('.', '\\.')}`));
  }
  assert.strictEqual(bash('fastapi_db_extension').stdout.trim(), '.dump');
});

test('Restore: the dump checked, restored into a database of its own, put in the app\'s place in one step, and the app\'s workers started again', () => {
  const dir = tmp('restore');
  fs.writeFileSync(path.join(dir, 'a.dump'), 'PGDMP\u0001\u000efake');
  const r = bash(`fastapi_import_db ${dir}/a.dump`, { CWD: dir });
  assert.strictEqual(r.status, 0, r.stderr + r.stdout);
  const steps = ['pg_restore --list', 'CREATE DATABASE app_restore', 'pg_restore -U postgres -d app_restore --no-owner --no-privileges --exit-on-error',
    'ALTER DATABASE app WITH ALLOW_CONNECTIONS false', 'pg_terminate_backend(pid, 5000)', '-c BEGIN -c ALTER DATABASE app RENAME TO app_before_restore -c ALTER DATABASE app_restore RENAME TO app -c COMMIT',
    'DROP DATABASE app_before_restore WITH (FORCE)', 'ddev exec -s fastapi -d / proc=', 'health-check'];
  const at = steps.map((s) => r.calls.indexOf(s));
  assert.ok(at.every((i) => i >= 0), `${JSON.stringify(steps.filter((s, i) => at[i] < 0))}\n${r.calls}`);
  assert.deepStrictEqual([...at].sort((x, y) => x - y), at, 'in order');
  assert.match(r.stdout, new RegExp(`This replaces the database of ${path.basename(dir)} \\(Postgres 18, app\\) with a\\.dump\\.\\nThe database of ${path.basename(dir)} is now a\\.dump\\.`));
  // A gzipped SQL dump that ends where pg_dump ends it goes in through psql.
  fs.writeFileSync(path.join(dir, 'b.sql.gz'), zlib.gzipSync('--\n-- PostgreSQL database dump\n--\nCREATE TABLE x ();\n--\n-- PostgreSQL database dump complete\n--\n\n\\unrestrict k1\n\n'));
  const sql = bash(`fastapi_import_db ${dir}/b.sql.gz`, { CWD: dir });
  assert.strictEqual(sql.status, 0, sql.stderr);
  assert.match(sql.calls, /^ddev exec -s postgres -d \/ psql -U postgres -d app_restore -v ON_ERROR_STOP=1 -q$/m);
  assert.doesNotMatch(sql.calls, /pg_restore/);
});

test('Restore refuses a file that is not a whole dump, and a restore that fails leaves the app\'s database as it was', () => {
  const dir = tmp('refuse');
  fs.writeFileSync(path.join(dir, 'cut.sql.gz'), zlib.gzipSync('--\n-- PostgreSQL database dump\n--\nCREATE TABLE x ();\n'));
  fs.writeFileSync(path.join(dir, 'notes.dump'), 'not a dump');
  fs.writeFileSync(path.join(dir, 'a.dump'), 'PGDMP\u0001\u000efake');
  for (const file of ['cut.sql.gz', 'notes.dump']) {
    const r = bash(`fastapi_import_db ${dir}/${file}`, { CWD: dir });
    assert.strictEqual(r.status, 1, file);
    assert.match(r.stderr, new RegExp(`${file.replace('.', '\\.')} is not a dump of a Postgres database \\(pg_dump's custom format, or its gzipped SQL\\)\\. Nothing was changed\\.`));
    assert.strictEqual(r.calls, '', 'nothing ran');
  }
  let r = bash(`fastapi_import_db ${dir}/a.dump`, { CWD: dir, FAIL: 'list' });
  assert.strictEqual(r.status, 1);
  assert.match(r.stderr, /a\.dump is not a whole dump: pg_restore cannot read its list\. Nothing was changed\./);
  assert.doesNotMatch(r.calls, /CREATE DATABASE/);
  r = bash(`fastapi_import_db ${dir}/a.dump`, { CWD: dir, FAIL: 'restore' });
  assert.strictEqual(r.status, 1);
  assert.match(r.stderr, /a\.dump did not go in whole\. The database of .* is as it was\./);
  assert.match(r.calls, /DROP DATABASE IF EXISTS app_restore WITH \(FORCE\)\n?$/, 'the half-restored database goes');
  assert.doesNotMatch(r.calls, /RENAME|ALLOW_CONNECTIONS|proc=/, 'the app\'s database is not touched');
  r = bash(`fastapi_import_db ${dir}/a.dump`, { CWD: dir, FAIL: 'swap' });
  assert.strictEqual(r.status, 1);
  assert.match(r.stderr, /The restored database could not take the place of app: the database of .* is as it was\./);
  assert.match(r.calls, /ALTER DATABASE app WITH ALLOW_CONNECTIONS true -c DROP DATABASE IF EXISTS app_restore WITH \(FORCE\)\n?$/, 'the old database is open again, and the restored one goes');
  assert.doesNotMatch(r.calls, /proc=/, 'no restart');
});

/** A folder laid out as /proc is, for the restart script: each process its command line and its parent. */
function procs(list: Array<[number, number, string[]]>) {
  const dir = tmp('proc');
  for (const [pid, ppid, argv] of list) {
    fs.mkdirSync(path.join(dir, String(pid)));
    fs.writeFileSync(path.join(dir, String(pid), 'cmdline'), argv.join('\0') + '\0');
    fs.writeFileSync(path.join(dir, String(pid), 'status'), `Name:\tx\nState:\tS\nPPid:\t${ppid}\n`);
  }
  return dir;
}

test('the restart of the app\'s workers: SIGHUP to FastAPI\'s server, never to the script that looks for it, then the old workers gone', () => {
  const script = bash('fastapi_reload_script').stdout;
  const worker = ['/app/.venv/bin/python', '-c', 'from multiprocessing.spawn import spawn_main; spawn_main(tracker_fd=5, pipe_handle=7)', '--multiprocessing-fork'];
  const proc = procs([
    [5, 0, ['bash', '-c', script]],
    [70, 0, ['/app/.venv/bin/python', '/app/.venv/bin/fastapi', 'run', '--workers', '2', '--port', '8000']],
    [79, 70, ['/app/.venv/bin/python', '-c', 'from multiprocessing.resource_tracker import main;main(4)']],
    [80, 70, worker],
    [81, 70, worker],
    [90, 1, worker],
  ]);
  const log = path.join(proc, 'kill.log');
  const stand = `kill() { echo "kill $*" >> ${log} ; rm -rf ${proc}/80 ${proc}/81 ; }`;
  const r = spawnSync('bash', ['-c', `${stand}\n${script}`], { encoding: 'utf8', env: { ...process.env, PROC: proc }, timeout: 20000 });
  assert.strictEqual(r.status, 0, r.stderr);
  assert.strictEqual(fs.readFileSync(log, 'utf8'), 'kill -HUP 70\n', 'the server, not the script (5) nor another tree\'s worker (90)');
  assert.ok(fs.existsSync(path.join(proc, '79')), 'the resource tracker is not waited for');
  const none = procs([[5, 0, ['bash', '-c', script]], [80, 1, worker]]);
  const n = spawnSync('bash', ['-c', `kill() { echo "kill $*" >> ${none}/kill.log ; }\n${script}`], { encoding: 'utf8', env: { ...process.env, PROC: none }, timeout: 20000 });
  assert.strictEqual(n.status, 1, 'no server: nothing to restart');
  assert.ok(!fs.existsSync(path.join(none, 'kill.log')), 'and no signal sent');
});

test('the builder takes the runtimes it is proven on, and never a flag that would take the name PATH', () => {
  const args = read('scripts/args/arg-fastapi.sh');
  const parser = args.slice(args.indexOf('\n', args.indexOf('<<ARGEOF')) + 1, args.lastIndexOf('\nARGEOF')).replace(/\$\{[a-z_]+\}/g, '');
  const py = `import argparse, json, sys\nparser = argparse.ArgumentParser()\n${parser}\nprint(json.dumps(vars(parser.parse_args(sys.argv[1:]))))`;
  const parse = (...argv: string[]) => spawnSync('python3', ['-I', '-c', py, ...argv], { encoding: 'utf8' });
  const ok = parse('app1', '--runtime', 'podman', '-s', 'https://example.com/a.git', '-r', 'main', '-p', 'api', '-i', '-a', '-l');
  assert.strictEqual(ok.status, 0, ok.stderr);
  assert.deepStrictEqual(JSON.parse(ok.stdout), { PROJECT_NAME: 'app1', RUNTIME: 'podman', source: 'https://example.com/a.git', ref: 'main', APP_PATH: 'api', install: true, add_users: true, launch: true });
  assert.strictEqual(JSON.parse(parse('app1').stdout).RUNTIME, '_none_');
  assert.notStrictEqual(parse('app1', '--runtime', 'lando').status, 0, 'a runtime it is not proven on');
  const src = read('scripts/functions/fun-fastapi.sh');
  assert.match(src, /^readonly FASTAPI_RUNTIMES='ddev docker podman kubernetes';$/m);
});

test('the first feature names no framework or platform in the words of a step', () => {
  const feature = read('testing/site.feature');
  const steps = feature.split('\n').filter((l) => /^\s*(Given|When|Then|And|But) /.test(l));
  assert.ok(steps.length >= 10);
  for (const s of steps) assert.doesNotMatch(s.replace(/"[^"]*"/g, '""'), /fastapi|python|react|vite|node|drupal|wordpress|joomla/i, s);
});
