---
name: fastapi-scenarios
description: The phrases of the FastAPI step pack (@webship-js/fastapi-steps) for webship-js scenarios of a FastAPI app built in the container-based Webship Workspace (DDEV by default) with cmd-fastapi-project.sh — its API with no browser (signed in through its own token address, refusals field by field, answers checked against the schema it documents), its interactive docs, and its front end as it uses the API. Use when writing or fixing a feature for such an app, or when a step about its API, its docs or its front end does not match.
---

# Scenarios for a FastAPI app

A FastAPI app is an API first: it answers in JSON, documents every operation in an OpenAPI schema (the source of its
interactive docs at /docs), hands out a bearer token for a user name and a password, and refuses bad input with a 422
whose `detail` names each field and the reason. The official full-stack template, the app `cmd-fastapi-project.sh`
builds, puts a browser front end on top of it. The pack's steps work on all three and wait on the app's own signals,
never for a fixed time. The workspace is container-based (DDEV by default).

## The book

For any automated functional testing in this work (a Gherkin feature, a step definition, choosing a
step, a test run and its failures), read the book *Automated Functional Testing Recipes* first.

- **Where.** Use the first that exists: `.claude/automated-functional-testing-recipes/` in the project,
  `~/.claude/automated-functional-testing-recipes/` (installed by webship/webship-js-ai-agent,
  webship/webship-js-skills or webship/ai-agents), or
  https://github.com/webship/webship-js-ai-agent/tree/2.0.x/automated-functional-testing-recipes
- **How.** Its `README.md` first, then the chapter that matches the task (one file per chapter,
  named by its subject), not the single complete file.
- **Which wins.** The installed webship-js package and the step pack are the source of truth for
  step phrasing. When they differ from the book, follow them and say so.
- **For FastAPI.** Start with `ch11-api-testing-recipes.md` (requests, answers and their shapes),
  `ch10-authentication-authorization.md` (a token, who may do what, and a refusal),
  `ch27-testing-spa.md` (a front end that changes its views without page loads) and
  `ch44-javascript-and-friendly-errors.md` (the browser's errors, and the one known one let through).

## Setting it up

`bash cmd-tools-testing.sh <app>` in the app's sites folder adds webship-js, the pack, the accounts `admin` and `user`
(worldParameters.users, their passwords from FASTAPI_ADMIN_PASSWORD and FASTAPI_USER_PASSWORD) and, for the template,
the one known error its pages log (the 404 of /vite.svg, let through by its address alone). `bash cmd-tools-testing.sh
<app> --run` runs the suite; `--list-steps` lists every phrase.

## The phrases

The API, with no browser (webship-js's own API steps send the requests; set `Given the API base URL is "/"` first):

- `Given I am signed in to the API as "admin"`: every request after it is signed with the account's token.
- `Then the API should have refused "password" with "at least 8 characters"`: a 422, field by field.
- `Then the API should have said "Incorrect email or password"`: a refusal that is a sentence.
- `Then the API's answer should match its documented schema`.
- `Then the API should document "POST /api/v1/users/signup"`.

The docs (Swagger UI, with JavaScript):

- `When I open the API docs` (it says which host the browser could not reach when the docs' script did not load).
- `Then the API docs should list "POST /api/v1/login/access-token"`.
- `When I authorize the API docs as "admin"`.
- `When I try out "GET /api/v1/users/me" in the API docs`, and `… in the API docs with:` a JSON doc string.
- `Then the API docs should show the answer 422 saying "String should have at least 8 characters"`.

The front end, as it uses the API (with JavaScript):

- `Given I am signed in to the app as "user"`: the token goes where the front end keeps it.
- `When I wait for the app's API calls to finish`.
- `Then the app should have called "POST /api/v1/items/"`, then `Then the app's call should have been accepted` or
  `… refused with "…"`.
- `Then the app should show the message "Item created successfully"`, and `When I wait for the app's messages to go`
  before pressing what a toast covers.
- `Then the app should have sent me to "/login" with a whole page load`.
- `Then the app should show its not-found page`.
- `Then the "Title" field should say "Title is required"`.

## The traps

- An address the app does not know answers 200 in a browser (the front end's not-found page) and 404 to a script:
  judge "not found" by the page.
- A refusal is logged by the browser as a console error: tag a scenario that expects one `@js-warn`, and say why in a
  comment above it. Keep the error mode at fail everywhere else.
- A scenario that makes something names it "Webship test …" (an account: `webship.test.…@example.com`) and carries
  `@removes-test-content`: the managing account removes it after the scenario, and the counts are checked.
- A wrong token is noticed on the app's next call; the template retries it four times before it loads its login page,
  and the step waits for that on purpose.
- The docs load Swagger UI from a CDN: a machine that cannot reach it gets an empty docs page.
- Without JavaScript only the API's scenarios run: the front end and the docs need it (`@needs-javascript`).

## Examples

- `examples/api.feature`: the API, signed in, refused field by field, against its schema.
- `examples/items.feature`: the front end adding an item, and a title it refuses before it sends anything.
- `examples/docs.feature`: the docs, authorized, tried out, and a refusal they show.

Run one with `bash cmd-tools-testing.sh <app> --run --path tests/features/api.feature`.
