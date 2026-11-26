Build a FastAPI app in a sites folder, serve it, and prove it with its first webship-js feature.

The launch command below is for Claude Code, the default; the text between the triple quotes can be given to another AI CLI as it is.

```
claude --permission-mode bypassPermissions """
Build the FastAPI app named <name> in this sites folder, serve it and test it with webship-js
# ~/workspace/<dev|test|sandboxes|demos> · https://<name>.ddev.site · container-based (DDEV by default)
# the builder deletes a project of the same name first: stop if <name> is an app somebody still needs
# nothing on the host: no python, pip, uv, npm or bun outside the app's container
# a feature to write or a run to read: the book Automated Functional Testing Recipes first (its README.md, then the matching chapter), from .claude/automated-functional-testing-recipes/ in the project, ~/.claude/automated-functional-testing-recipes/ or https://github.com/webship/webship-js-ai-agent/tree/2.0.x/automated-functional-testing-recipes

1. bash cmd-fastapi-project.sh <name> --install --add-users   (the official full-stack template, its Postgres 18, its two accounts)
2. bash cmd-tools-testing.sh <name>   (webship-js, the FastAPI step pack, the accounts, a first feature)
3. bash cmd-tools-testing.sh <name> --run, and read every failure from its message and hint
4. Add one scenario of your own for <what the app should do>, from the skill fastapi-scenarios, and run it

Report the address, what ran, what passed, and what you changed.
"""
```
