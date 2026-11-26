Write webship-js scenarios for a FastAPI app that is already built: its API, its docs and its front end.

The launch command below is for Claude Code, the default; the text between the triple quotes can be given to another AI CLI as it is.

```
claude --permission-mode bypassPermissions """
Write webship-js scenarios for the FastAPI app <name> in this sites folder: <what to cover>
# ~/workspace/<dev|test|sandboxes|demos> · https://<name>.ddev.site · container-based (DDEV by default)
# the phrases: the skill fastapi-scenarios; every phrase the suite has: bash cmd-tools-testing.sh <name> --list-steps
# before writing: the book Automated Functional Testing Recipes (its README.md, then ch11-api-testing-recipes.md and ch10-authentication-authorization.md), from .claude/automated-functional-testing-recipes/ in the project, ~/.claude/automated-functional-testing-recipes/ or https://github.com/webship/webship-js-ai-agent/tree/2.0.x/automated-functional-testing-recipes

1. Read the app's schema at https://<name>.ddev.site/docs (or /api/v1/openapi.json for the template) and its pages
2. Write tests/features/<topic>.feature: the API first (no browser), then the front end and the docs (@needs-javascript)
3. Anything a scenario makes is "Webship test …" and the scenario carries @removes-test-content
4. A scenario that expects a refusal carries @js-warn and a comment saying why
5. bash cmd-tools-testing.sh <name> --run --path tests/features/<topic>.feature, until it passes twice in a row

Report the scenarios, what they check, and the runs.
"""
```
