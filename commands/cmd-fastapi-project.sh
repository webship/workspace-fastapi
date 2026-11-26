#!/usr/bin/env bash

# workspace-name: FastAPI (full-stack template)

# Installed by the FastAPI plugin (plugins.sh --install fastapi); __WORKSPACE__ is the workspace it was installed into.
#
# Make a FastAPI app from the official full-stack template (release 0.12.0), or take one laid out as it is from its
# repository with --source, build the app's own image (its backend/Dockerfile: bun builds the front end, Python runs
# FastAPI) and serve it from a container of its own, on a Postgres 18 of its own. Python, the app's language, runs in
# the app's container, never on the machine. With --install the app is started (its migrations and first superuser
# made by the template's prestart.sh) and checked; with --add-users its accounts are made through its API. The
# workspace is container-based (DDEV by default, at https://<name>.ddev.site); --runtime docker, podman or kubernetes
# builds it on Docker Compose, Podman or a Kubernetes cluster instead, at the address that runtime gives.

# Bootstrap.
# Find the workspace tooling from this script, so a fresh clone needs no setup.
WORKSPACE_SCRIPTS="${WORKSPACE_SCRIPTS:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../core/scripts" && pwd)}";
source ${WORKSPACE_SCRIPTS}/bootstrap.sh || exit 1 ;

# Load workspace settings.
eval $(parse_yaml ${WORKSPACE_CONFIG}/workspace.__WORKSPACE__.settings.yml);

# Where the app comes from: nothing means the official full-stack template.
app_source="";
app_source_ref="";
app_source_path="";

# Distribution.
distribution_name="fastapi";
distribution_title="FastAPI";
distribution_webroot="app";

ARGPARSE_DESCRIPTION="Build a ${distribution_title} project in __WORKSPACE__"
# The args file comes with the plugin: core/scripts/plugins/fastapi/ is where plugins.sh --install puts it.
source ${WORKSPACE_SCRIPTS}/plugins/fastapi/args/arg-fastapi.sh || exit 1 ;

shift $#;

fastapi_build ;
