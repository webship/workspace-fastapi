---
description: Test a FastAPI app of the Webship Workspace with webship-js and the FastAPI step pack — set the testing stack up when it is missing, match every step, run the suite (or one feature, or a tag) with JavaScript and without, and read why a scenario fails.
argument-hint: '<app> [tests/features/<name>.feature | @tag]'
---

# /fastapi-test

Test the FastAPI app named in: `$ARGUMENTS`

`$ARGUMENTS` stands for what was typed after the command: the app's name, then a feature or a tag to run alone.

The workspace is container-based (DDEV by default). Work in the sites folder the app is in (`~/workspace/dev` unless
told otherwise).

1. When the app is not there, build it: `bash cmd-fastapi-project.sh <app> --install --add-users`.
2. When the app has no testing stack yet (no `cucumber.js` in its folder), set it up: `bash cmd-tools-testing.sh <app>`.
3. Match every step before running: `bash cmd-tools-testing.sh <app> --dry-run`. An undefined step is a phrase the pack
   or webship-js does not have: `bash cmd-tools-testing.sh <app> --list-steps` lists them, and the skill
   `fastapi-scenarios` says which one to use.
4. Run it: `bash cmd-tools-testing.sh <app> --run`, or `--run --path tests/features/<name>.feature`, or
   `--run --tags @<tag>`. The API's scenarios run in a browser without JavaScript too; the front end's and the docs'
   need it.
5. Read a failure from its message and hint: the pack says what it expected, what it found and what to try. A refused
   call shows FastAPI's own reason; a page that did not load its docs names the host the browser could not reach.

Before you write or change a scenario, or read a failed run, read the book *Automated Functional
Testing Recipes* (its `README.md`, then the matching chapter):
`.claude/automated-functional-testing-recipes/` in the project,
`~/.claude/automated-functional-testing-recipes/`, or
https://github.com/webship/webship-js-ai-agent/tree/2.0.x/automated-functional-testing-recipes

Report what ran, what passed, and for each failure the step, its message, and the change you propose.
