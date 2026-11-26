/**
 * FastAPI for Webship Workspace: a plugin for FastAPI apps.
 *
 * What the package carries is placed by the installer from the manifest: the builder in the sites folders, its
 * functions, argparse and machine files (the project's compose services on DDEV, a first feature) under
 * core/scripts/plugins/fastapi/, its AI items (ai/) in the AI folders. The builder makes a FastAPI app from the official
 * full-stack template (or takes one laid out as it is from its repository), builds the app's own image and serves it
 * from a container of its own, on a Postgres 18 of its own. Python, the app's language, runs in the app's container,
 * never on the machine. The app's database is the plugin's to back up and restore (the core's database hook: pg_dump
 * and pg_restore). The step pack (@webship-js/fastapi-steps) goes into the testing setup of such an app with the core's
 * `cmd-tools-testing.sh <project>`. The dashboard needs nothing drawn for it: the builder is in the Build list because
 * it is a cmd-*-project.sh, the row menus are the core's, the AI items are listed like any other. What register() adds
 * is what the assistant is told.
 *
 * Everything the dashboard is asked for goes through `api`; this package requires nothing from the dashboard's own
 * files, so it can be installed from npm and removed without a trace.
 */

import type { PluginApi } from '@webship.co/workspace-plugin-api';

/** The plugin's name, which its functions are named after. */
export const PLATFORM = 'fastapi';

/** The commands the installer places in every sites folder. */
export const COMMANDS = ['cmd-fastapi-project.sh'];

/** The agents the installer places in the AI Agents folder. */
export const AGENTS = ['fastapi-app-builder', 'fastapi-tester'];

/** The skill the installer places in the AI Skills folder (a folder each, with its SKILL.md). */
export const SKILLS = ['fastapi-scenarios'];

/** The slash command the installer places in the AI Commands folder. */
export const AI_COMMANDS = ['fastapi-test'];

/** The prompts the installer places in the AI Prompts folder: whole launch commands for a new session. */
export const PROMPTS = ['fastapi-build-and-test', 'fastapi-scenarios-for-an-app'];

/** What the assistant is told about FastAPI in this workspace. */
export function assistantContext(): string {
  return [
    'FastAPI (a plugin, @webship.co/workspace-fastapi): its builder makes a FastAPI app and serves it from a container of its own, with',
    '`bash cmd-fastapi-project.sh <name> --install --add-users` from a sites folder (dev, test, sandboxes, demos): the app is the official',
    'full-stack template (release 0.12.0: FastAPI serving the API under /api/v1 and a React front end, built into the app\'s own image from',
    'its backend/Dockerfile), or a repository laid out as it is with --source, --ref and --path, at https://<name>.ddev.site. Python runs in the',
    'app\'s container, never on the machine. Its database is a Postgres 18 of its own (DDEV\'s db is omitted: DDEV 1.24.7 runs Postgres only up',
    'to 17), whose data the plugin backs up with pg_dump and restores with pg_restore through the row\'s Backup and Restore (the core\'s',
    'database hook). The template\'s prestart.sh runs its migrations and makes its first superuser, admin@example.com; --add-users makes the',
    'normal account user@example.com through the app\'s API. The app\'s source is in <name>/app/, its settings in <name>/.webship-fastapi/.',
    '`--runtime docker`, `podman` or `kubernetes` builds it on Docker Compose, Podman or a Kubernetes cluster instead of DDEV, at the address',
    'that runtime gives (the build prints it).',
    '`bash cmd-tools-testing.sh <name>` sets up webship-js with the step pack @webship-js/fastapi-steps on such an app: its steps sign in',
    'through the API\'s own token address, read its refusals field by field, check its answers against the schema it documents, use its',
    'interactive docs, and wait on the calls its front end sends.',
    `For building or fixing a FastAPI app (its image, its database, its accounts), hand over to the agent \`${AGENTS[0]}\`; for testing one, to \`${AGENTS[1]}\`.`,
    `The plugin also places the skill ${SKILLS.map((a) => `\`${a}\``).join(', ')} (the step pack's phrases) in ai-skills/,`,
    `the command ${AI_COMMANDS.map((a) => `\`/${a} <app>\``).join(', ')} in ai-commands/ and the prompts ${PROMPTS.map((a) => `\`${a}\``).join(' and ')} in ai-prompts/.`,
    'Never run python, pip, uv, npm or bun on the host for a project.',
  ].join(' ');
}

export function register(api: PluginApi): void {
  api.addAssistantContext(assistantContext);
}
