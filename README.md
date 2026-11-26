<p align="center"><img src="https://raw.githubusercontent.com/webship/workspace-fastapi/1.0.x/assets/logo.svg" alt="FastAPI icon" width="96"></p>

# @webship.co/workspace-fastapi

FastAPI for the [Webship Workspace](https://github.com/webship/workspace) dashboard: a builder that makes a FastAPI app
from the official full-stack template (or takes one laid out as it is from its repository), builds the app's own image
and serves it from a container of its own on a Postgres 18 of its own, the
[FastAPI step pack](https://github.com/webship/fastapi-steps) wired into the testing setup of that app, and its AI
items — two agents, a skill, a command and two prompts for building and testing FastAPI apps — each listed in the
workspace folder of its kind.

The app brings its own language in its own container. Python runs in the app's own image, built from its
`backend/Dockerfile`: for the template, bun builds the React front end, and Python 3.14 runs FastAPI, which serves the
API under `/api/v1`, its documented schema, its interactive docs and the built front end. Before the app serves, the
template's `prestart.sh` runs its migrations and makes its first superuser. Nothing of Python, uv or bun runs on the
machine.

The workspace is container-based (DDEV by default): an app is a row like any other, so the row menus the core draws
(start, stop, launch, backup, restore, clone, remove, tests) work on it, its Backup and Restore through the plugin's
own database hook. The builder builds on DDEV by default, and with `--runtime` on Docker Compose, Podman or a
Kubernetes cluster: see [Runtimes](#runtimes). It needs Webship Workspace 1.0.42 or newer, the core with the database
hook (webship/workspace#937), and says so on an older one before it makes anything.

## Use it

```bash
cd ~/workspace
bash core/scripts/plugins.sh --require fastapi --with-needs     # npm install into the dashboard
bash core/scripts/plugins.sh --activate fastapi --with-needs    # plugins.fastapi in settings.yml
bash core/scripts/plugins.sh --install fastapi                  # the builder, functions, args, AI items
bash core/scripts/plugins.sh --configure fastapi                # nothing to configure: it has no settings file
```

The same four steps are buttons on the dashboard's **Settings → Plugins** page. `--install` is idempotent.
`--uninstall` removes what it placed; an AI item you edited stays.

Everything the plugin carries lands in the folder it belongs to, when that folder is an active workspace folder:

| What | Lands in |
| --- | --- |
| `cmd-fastapi-project.sh` | every active sites folder: `dev/`, `test/`, `sandboxes/`, `demos/` |
| The agents `fastapi-app-builder`, `fastapi-tester` | `ai-agents/` |
| The skill `fastapi-scenarios` | `ai-skills/` |
| The command `/fastapi-test` | `ai-commands/` |
| The prompts `fastapi-build-and-test`, `fastapi-scenarios-for-an-app` | `ai-prompts/` |

There they are listed like any other item of the folder, and installed into Claude Code from there.

## What it needs

A workspace starts empty, so the manifest says what else this plugin needs (`needs`):

- one sites folder, for the builder: `dev`, `test`, `sandboxes`, `demos` (`dev` is the one added when none is there). The folder also carries `cmd-tools-testing.sh`, the Users tools and the backup script this plugin's hooks answer to.
- `ai-agents`, `ai-skills`, `ai-commands` and `ai-prompts`: the AI folders its agents, its skill, its command and its prompts are placed in.

`--require` says so, `--activate` and `--install` stop until the workspace has them, and `--with-needs` adds what is
missing first:

```bash
bash core/scripts/plugins.sh --activate fastapi --with-needs   # dev and the four AI folders are required, activated and installed first
bash core/scripts/plugins.sh --install fastapi
```

Everything the builder runs for an app runs in the app's own containers, through the container tool the workspace
already needs; the plugin asks for no command of its own on the machine. Making an app clones the template (or your
repository) with git, and the app's image is built from its own Dockerfile, which downloads its base images and its
packages.

## What the package holds

| Path | What it is |
| --- | --- |
| `commands/cmd-fastapi-project.sh` | The builder, in the Build list as **FastAPI (full-stack template)**, installed into every sites folder |
| `scripts/functions/fun-fastapi.sh` | The bash functions behind it, sourced by bootstrap once installed; the names the core's tools look for (`set_fastapi_users`, `add_fastapi_users`, `cancel_fastapi_users`, `testing_configure_fastapi`) and the database hook (`fastapi_is_project`, `fastapi_export_db`, `fastapi_import_db`, `fastapi_db_extension`) |
| `scripts/args/arg-fastapi.sh` | Its argparse; the Build form draws the builder's flags from it |
| `scripts/docker-compose.fastapi.yaml` | On DDEV, the app's service and Postgres's, copied into the project's `.ddev/` |
| `testing/site.feature` | The first feature the template gets when testing is set up |
| `ai/agents/fastapi-app-builder.md` | The agent that builds and fixes apps: the app's image, its Postgres, its accounts, its database's backup and restore |
| `ai/agents/fastapi-tester.md` | The agent that writes and runs scenarios with the step pack: the API first, then the docs and the front end |
| `ai/skills/fastapi-scenarios/` | The skill: the step pack's phrases, the traps found on the template, three example features |
| `ai/commands/fastapi-test.md` | The slash command `/fastapi-test <app>`: set up when missing, match every step, run, report |
| `ai/prompts/fastapi-build-and-test.md`, `fastapi-scenarios-for-an-app.md` | Two prompts: whole launch commands for a new session |
| `src/index.ts` | `register(api)`: what the assistant is told about FastAPI here |
| `features/fastapi.feature`, `features/fastapi-runtimes.feature` | Scenarios for the dashboard's own browser suite |

The `workspacePlugin` block in `package.json` is the manifest the installer reads.

## What is different from a platform

| | WordPress (a platform) | FastAPI |
| --- | --- | --- |
| What is built | A WordPress site | A FastAPI app: the official full-stack template at release 0.12.0, or an app laid out as it is from its repository |
| Project | `--project-type=wordpress` | `--project-type=generic --webserver-type=generic`, DDEV's database omitted: the app's own image serves it, on its own Postgres |
| The language | PHP, in the container tool's image | Python in the app's own image (its `backend/Dockerfile`): a service of the project on DDEV; on Docker Compose, Podman and Kubernetes the stack of the core's runtime layer (`rt_stack image`, `rt_serve`) |
| The database | DDEV's own, or the runtime's | Postgres 18 of its own, pinned by digest, its data in a volume named after the project: a service of the project on DDEV (`.ddev/docker-compose.fastapi.yaml`), `rt_service postgres` on another runtime |
| Recognised by | The project type | On DDEV a file the builder writes, `.ddev/config.fastapi.yaml` (it also records where the app came from); on another runtime its claim, `platform: fastapi` in the `x-webship` block of `compose.yaml` |
| Accounts | WP-CLI | The app's API: its first superuser is the app's own, the normal account is made through `/api/v1/users/` |
| Backup and Restore | DDEV's `export-db` and `import-db` | The plugin's database hook: `pg_dump` and `pg_restore` in the app's Postgres |
| Testing | The WordPress pack | The FastAPI pack: the API without a browser, the interactive docs, and the front end as it uses the API |

## The commands

Run it from a sites folder. `--help` is safe.

### Build and serve an app

```bash
cd ~/workspace/dev
bash cmd-fastapi-project.sh fapp --install --add-users                 # the template, started, with its two accounts
bash cmd-fastapi-project.sh fown --install --source https://github.com/<you>/<app>.git --ref main
bash cmd-fastapi-project.sh fapp --install --add-users --runtime docker    # on Docker Compose instead of DDEV
bash cmd-fastapi-project.sh fapp --install --runtime kubernetes            # on the workspace's Kubernetes cluster
```

| Flag | What it does |
| --- | --- |
| `--install` | Start the app (its image, its Postgres, its migrations and first superuser) and check that it answers its health check at its address (`https://<name>.ddev.site` on DDEV) |
| `--add-users` | Make the default accounts too, through the app's API (see [Users](#users)) |
| `--runtime ddev\|docker\|podman\|kubernetes` | The container runtime to build on (default: DDEV, or `container.runtime` of `settings.yml`); see [Runtimes](#runtimes) |
| `--source <git url>` | A repository of a FastAPI app laid out as the full-stack template is, instead of the template |
| `--ref <branch or tag>` | A branch or a tag of that repository (default: its default branch) |
| `--path <folder>` | The folder of the app in that repository, for a repository of several apps |
| `--launch` | Open the app in a browser when it is ready |

The builder deletes a project of the same name first (its containers and its Postgres volume), takes the app into
`app/`, configures the project, writes the app's settings and Postgres's into `.webship-fastapi/` (only you can read
them: a secret key and a database password of the project's own, made once and kept by a later build), and builds the
app's image. With `--install` it starts the project and waits for the app's health check.

**The template** is the official full-stack FastAPI template (github.com/fastapi/full-stack-fastapi-template, MIT),
cloned at its release 0.12.0: a FastAPI backend with SQLModel and Alembic on Postgres, a React front end with
TanStack Router, accounts with an OAuth2 token, items, and mails to the project's mail catcher.

**An app of your own** must be laid out as the template is: `backend/Dockerfile` (the image that serves it) and
`backend/scripts/prestart.sh` (what runs before it serves: migrations, a first superuser). Any other repository stops
the build with a message, before a project is configured.

The project's folder holds the app's source in `app/` and the builder's own files in `.webship-fastapi/`. After a
change to the app, build it again (`bash cmd-fastapi-project.sh <name> --install`; the database goes with the project,
so take a Backup first), or on DDEV rebuild its image in place with `ddev restart`.

### Its database

The app's Postgres is version 18, the template's, pinned by digest, with its data in a volume named after the project:
removing the project removes it, and a new build starts empty. DDEV 1.24.7 runs Postgres only up to 17 as its own
database, so the builder omits DDEV's database and the app's Postgres is a service of the project. DDEV's own database
tools do not reach it: `ddev snapshot`, and DDEV's own `export-db` and `import-db`, work on DDEV's database, which this
project does not have.

The plugin declares the core's database hook instead (webship/workspace#937, core 1.0.42), which the row's Backup and
Restore ask first, on every runtime:

- **Backup** writes a `pg_dump` of the app's database in its custom format (`<archive>-db.dump`) beside the project's
  archive, and checks that it is one.
- **Restore** (the row's Import) lists the project's own dumps, checks that the chosen one is whole (pg_restore can
  read its list, or a gzipped SQL dump ends where pg_dump ends it), exports the database as it is first, restores the
  dump into a database of its own, and only then puts it in the app's place: the old database takes no new
  connections, its open ones go, and the two are renamed in one transaction. The app's workers are then started again
  with new connections. A restore that fails leaves the app's database as it was.
- A file named `*.sql.gz` (the safety dump before a remove, a clone) is a gzipped SQL dump instead.

On Docker Compose, Podman and Kubernetes the row's menu lists Export and Import for this project from Webship
Workspace 1.0.43 (webship/workspace#942). Before it, the row's Backup works as above, and a restore is the
terminal's, below.

The same works on a terminal, in the project's folder, through the workspace's runtime verbs (DDEV's own `ddev
export-db` there is DDEV's, which has no database to export):

```bash
cd ~/workspace/dev/fapp
bash ~/workspace/core/scripts/runtime-verb.sh export-db --file=../fapp-before.dump
bash ~/workspace/core/scripts/runtime-verb.sh import-db --file=../fapp-before.dump
```

### Test an app

```bash
bash cmd-tools-testing.sh fapp                                   # webship-js, the step pack, the accounts, a first feature
bash cmd-tools-testing.sh fapp --run --path tests/features/site.feature
```

The testing setup adds `@webship-js/fastapi-steps` to the project, lists its step definitions in `cucumber.js`, adds
the accounts the scenarios name (`admin` and `user`, their passwords from `FASTAPI_ADMIN_PASSWORD` and
`FASTAPI_USER_PASSWORD`, the workspace's by default) and, for the template, writes `tests/features/site.feature` and
lets the one known error its pages log through, by its address alone: the template's `index.html` links `/vite.svg`,
which its build does not ship, so every page logs a 404 for it. Every other browser error still counts. An app of your
own gets no first feature and no allowed error: it has its own pages. The setup changes nothing in a project that is
not an app of this builder.

The API's scenarios need no browser, and run without JavaScript too; the docs' and the front end's need it.

```gherkin
Feature: Accounts
  Scenario: Signed in, the API knows the account
    Given the API base URL is "/"
    And I am signed in to the API as "user"
    When I send a GET request to "/api/v1/users/me"
    Then the API response code should be 200
    And the API's answer should match its documented schema

  Scenario: A sign-up refused field by field
    Given the API base URL is "/"
    When I send a POST request to "/api/v1/users/signup" with body:
      """
      {"email": "not-an-address", "password": "short"}
      """
    Then the API response code should be 422
    And the API should have refused "password" with "at least 8 characters"
```

### Runtimes

The commands are the same on every runtime: the builder speaks DDEV's verbs, and on another runtime the core's layer
(webship/workspace#694, #841 and #900) gives each verb its meaning there: the app's own image as the stack, built by
the runtime's engine, its server as the web container's own, and Postgres as a service of the project.

| Runtime | The address of the app | Proven with this builder |
| --- | --- | --- |
| DDEV (the default) | `https://<name>.ddev.site` | PROOF-DDEV |
| Docker Compose (`--runtime docker`) | `http://127.0.0.1:<port>`, a free port kept in `compose.yaml` | PROOF-DOCKER |
| Podman (`--runtime podman`) | `http://127.0.0.1:<port>` | PROOF-PODMAN |
| Kubernetes (`--runtime kubernetes`) | `http://<node address>:<NodePort>` | PROOF-KUBERNETES |

A project of the builder is known by DDEV's file on DDEV and by its claim on another runtime, so the testing setup,
the Users tools, the database hook and the dashboard's row work the same on each. Lando and Docksal are runtimes of the
workspace too, not proven with this builder yet: it says so and stops, before anything is made.

### Users

| Account | Mail | Made by |
| --- | --- | --- |
| `admin` | `admin@example.com` | The app itself: the template's prestart makes its first superuser from the settings the builder writes |
| `user` | `user@example.com` | `--add-users`, or `cmd-tools-add-users.sh <name> fastapi`: through the app's API, as its first superuser |

Both have the workspace's password. `cmd-tools-cancel-users.sh <name> fastapi` makes `user` inactive through the API;
its items stay, and the first superuser is never touched.

## The AI items

| Item | Kind | What it is for |
| --- | --- | --- |
| `fastapi-app-builder` | agent | Builds and fixes FastAPI apps: the app's image and its Postgres, its accounts through its API, its database's backup and restore, what to read when it does not answer |
| `fastapi-tester` | agent | Writes and runs scenarios with the step pack: the API first, then the docs and the front end, test content removed and counted, never a fixed wait |
| `fastapi-scenarios` | skill | The step pack's phrases, the traps found on the template, three example features that pass on it |
| `/fastapi-test <app>` | command | Sets the pack up when missing, matches every step, runs, reports |
| `fastapi-build-and-test` | prompt | Builds an app and proves it with its first feature |
| `fastapi-scenarios-for-an-app` | prompt | Writes and runs the scenarios of an app of the workspace: its API, its docs and its front end |

Every item says the workspace is container-based (DDEV by default), and the agents and the skill send the reader to
the book *Automated Functional Testing Recipes* first.

## Develop it

```bash
npm install
npm test        # builds, then the unit tests: the manifest, the scripts, the AI items, the needs
npm run lint    # the TypeScript compiler, no output
```

CI runs the same on Node.js 24 and 26, checks that every shell script parses, and runs the plugin's webship-js
features against a dashboard with the plugin installed (the reusable workflow
`webship/workspace/.github/workflows/plugin-browser-suite.yml`). Before the features it builds the app the manifest
names (`featuresSite`: `cmd-fastapi-project.sh ci-fastapi --install --add-users --runtime docker`), so the scenarios of
`features/fastapi-runtimes.feature` tagged `@needs-runtime-docker` drive a real app on Docker Compose; the Podman and
Kubernetes ones run where such an app is.
`tests/fixtures/step-definitions.txt` holds the step definitions of the step pack and of webship-js, read from their
packages: every phrase an AI item shows must match one of them.

## License

ISC (see `LICENSE`).

## Logo

The FastAPI icon is from github.com/fastapi/full-stack-fastapi-template (MIT), unmodified. FastAPI is a registered
trademark of its owner; this plugin is not affiliated with or endorsed by the FastAPI project. The icon is not covered
by this package's licence.
