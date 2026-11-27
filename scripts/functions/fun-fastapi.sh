#!/usr/bin/env bash

# FastAPI for the Webship Workspace: make a FastAPI app from the official full-stack template (or take one from its
# repository), build the app's own image and serve it from a container of its own, on a Postgres of its own, and wire
# the FastAPI step pack into the testing setup of that app.
#
# Placed by `plugins.sh --install fastapi` in core/scripts/plugins/fastapi/functions/, where bootstrap sources it after
# the core's own functions. Everything runs in containers, never on the host: Python is the app's language, and the app
# runs in its own image, the template's backend/Dockerfile (bun builds the front end, Python 3.14 runs FastAPI, which
# serves the API under /api/v1 and the built front end). Before it serves, the template's prestart.sh runs its
# migrations and makes its first superuser.
#
# Postgres is the app's own, at the template's version (18), pinned by digest, its data in a volume named after the
# project: DDEV 1.24.7 runs postgres only up to 17 as its own db, so DDEV's db is omitted and DDEV's own database tools
# (export-db, import-db, snapshot) do not reach it. The plugin declares the core's database hook instead
# (webship/workspace#937, core 1.0.42): fastapi_export_db (pg_dump) and fastapi_import_db (pg_restore, after a check that
# the dump is whole), which the row's Backup and Restore ask first.
#
# The runtimes:
#   - DDEV (the default): a generic project whose web container keeps the mail catcher; the app and Postgres are services
#     of the project (.ddev/docker-compose.fastapi.yaml), and the router sends the project's address to the app.
#   - Docker Compose, Podman and Kubernetes (--runtime docker, podman, kubernetes): the core's runtime layer
#     (webship/workspace#841): the app's image as the stack (rt_stack image), its server as the web container's own
#     (rt_serve), Postgres as a service of the project (rt_service); at http://127.0.0.1:<port>, or on Kubernetes (kind)
#     at the node's address and a NodePort.
# Lando and Docksal are not proven for it yet: asked for one, the builder says so and changes nothing.
#
# The project's folder: app/ (the template at its release, or a repository cloned with --source) and .webship-fastapi/
# (the app's settings and Postgres's, which only you can read, and the script that serves the app on another runtime).
#
# The container tool has no project type for FastAPI, so a project of this builder is recognised by its mark
# (.ddev/config.fastapi.yaml on DDEV, `platform: fastapi` in compose.yaml elsewhere), and these names are the ones the
# core's tools look for:
#   set_fastapi_users          the default accounts                         (cmd-tools-add-users.sh <project> fastapi)
#   add_fastapi_users          make them through the app's API              (the same tool, and --add-users of the builder)
#   cancel_fastapi_users       keep them from signing in (made inactive)    (cmd-tools-cancel-users.sh <project> fastapi)
#   testing_configure_fastapi  the step pack in the testing stack           (cmd-tools-testing.sh <project>)
#   fastapi_is_project, fastapi_export_db, fastapi_import_db, fastapi_db_extension
#                              the database hook                            (the row's Backup and Restore, core 1.0.42)

# The step pack an app is tested with, and the release line it is required at.
readonly FASTAPI_STEPS_PACKAGE='@webship-js/fastapi-steps';
readonly FASTAPI_STEPS_VERSION='^2.0.0';

# The official full-stack template (https://github.com/fastapi/full-stack-fastapi-template, MIT), at the release the
# builder is proven with.
readonly FASTAPI_TEMPLATE_REPOSITORY='https://github.com/fastapi/full-stack-fastapi-template.git';
readonly FASTAPI_TEMPLATE_VERSION='0.12.0';

# Postgres 18, the template's version, pinned by digest (docker.io/library/postgres:18).
readonly FASTAPI_POSTGRES_IMAGE='docker.io/library/postgres@sha256:c699303802144847d238196173655dbbecf7a96aeca1565f2b02eb671a1f0b6b';

# The port the app listens on in its container, its workers, the app's folder, and the builder's own folder.
readonly FASTAPI_PORT='8000';
readonly FASTAPI_WORKERS='2';
readonly FASTAPI_APP='app';
readonly FASTAPI_OWN='.webship-fastapi';

# The extension of the plugin's own dumps (pg_dump's custom format).
readonly FASTAPI_DB_EXTENSION='.dump';

# The runtimes an app is built on.
readonly FASTAPI_RUNTIMES='ddev docker podman kubernetes';

# The default accounts, the ones a scenario signs in as: the app's first superuser (made by the template's prestart from
# FIRST_SUPERUSER) and a normal account (made through the app's API). Accounts are configuration, made once on the
# site; a test suite never creates or deletes one but its "Webship test …" ones, which it removes.
function set_fastapi_users() {
  users=(admin user);
  user_admin_name='admin@example.com' ; user_admin_mail='admin@example.com' ; user_admin_password='dD.123123ddd' ;
  user_admin_fullname='' ; user_admin_role='superuser' ;
  user_user_name='user@example.com' ; user_user_mail='user@example.com' ; user_user_password='dD.123123ddd' ;
  user_user_fullname='Webship user' ; user_user_role='user' ;
}

# The runtime of the project in this folder, or of a new build (--runtime, else the workspace's setting, else DDEV).
function fastapi_runtime() {
  if declare -f runtime_of > /dev/null ; then runtime_of ; else echo 'ddev' ; fi
}

# The address of the app in this folder: https://<name>.ddev.site on DDEV, http://127.0.0.1:<port> on Docker Compose and
# Podman, the node's address and a port on Kubernetes. Asked after `ddev config`.
function fastapi_url() {
  if declare -f rt_url > /dev/null ; then rt_url ; else echo "https://${PROJECT_NAME}.ddev.site" ; fi
}

# Is this folder a project of the FastAPI builder? On DDEV the builder leaves .ddev/config.fastapi.yaml in it; on another
# runtime it claims the project (`platform: fastapi` in the x-webship block).
function fastapi_is_project() {
  local project_path="$1";
  [ -f "${project_path}/.ddev/config.fastapi.yaml" ] && return 0 ;
  declare -f rt_is_platform > /dev/null && rt_is_platform "${project_path}" fastapi ;
}

# The service of the project the app runs in (DDEV: its own service; another runtime: the web container), and the one
# Postgres runs in.
function fastapi_app_service() {
  if [ "$(fastapi_runtime)" = 'ddev' ] ; then echo 'fastapi' ; else echo 'web' ; fi
}

# A command in the project's Postgres, its input passed on: DDEV's service, or the runtime's (rt_service).
function fastapi_pg() {
  ddev exec -s postgres -d / "$@" ;
}

# The SMTP host of the project's mail catcher: DDEV's web container keeps it; on another runtime it is the mail service.
function fastapi_smtp_host() {
  if [ "$(fastapi_runtime)" = 'ddev' ] ; then echo 'web' ; else echo 'mail' ; fi
}

# The app's settings and Postgres's (.webship-fastapi/env, .webship-fastapi/postgres.env), which only you can read: a
# secret key and a database password of the project's own, made once and kept on later builds; the first superuser with
# the workspace's password; the address the app writes into its mails and lets call it (FRONTEND_HOST); the mail catcher.
function fastapi_write_env() {
  local project_path="$1" base_url="$2" own secret dbpass ;
  own="${project_path}/${FASTAPI_OWN}" ;
  mkdir -p -m 700 "${own}" || return 1 ;
  secret="$(sed -n 's/^SECRET_KEY=//p' "${own}/env" 2> /dev/null)" ;
  dbpass="$(sed -n 's/^POSTGRES_PASSWORD=//p' "${own}/postgres.env" 2> /dev/null)" ;
  [ -n "${secret}" ] || secret="$(python3 -c 'import secrets; print(secrets.token_urlsafe(32))')" ;
  [ -n "${dbpass}" ] || dbpass="$(python3 -c 'import secrets; print(secrets.token_urlsafe(18))')" ;
  set_fastapi_users ;
  ( umask 077
    cat > "${own}/postgres.env" <<ENVEOF
# Postgres of this FastAPI app, made by the FastAPI builder of the workspace. Read by its container; never printed.
POSTGRES_PASSWORD=${dbpass}
POSTGRES_DB=app
ENVEOF
    cat > "${own}/env" <<ENVEOF
# The settings of this FastAPI app, made by the FastAPI builder of the workspace. Read by the app's container; never printed.
PROJECT_NAME=Full Stack FastAPI Project
SECRET_KEY=${secret}
FIRST_SUPERUSER=${user_admin_mail}
FIRST_SUPERUSER_PASSWORD=${user_admin_password}
DATABASE_URL=postgresql://postgres:${dbpass}@postgres:5432/app
FRONTEND_HOST=${base_url}
SMTP_HOST=$(fastapi_smtp_host)
SMTP_PORT=1025
SMTP_TLS=false
EMAILS_FROM_EMAIL=info@example.com
ENVEOF
  ) ;
}

# The app's settings put in the environment as a compose env file is read: each KEY=value line as it is, never
# through the shell (a value may have spaces, as the template's PROJECT_NAME does).
function fastapi_env_line() {
  local env_file="$1" ;
  echo "while IFS= read -r l ; do case \"\$l\" in ''|'#'*) ;; *=*) export \"\${l%%=*}=\${l#*=}\" ;; esac ; done < ${env_file}" ;
}

# The command the app's container runs: the app's settings, the template's prestart.sh (its migrations and first
# superuser: safe to run again), then FastAPI's server. Postgres is waited for first on another runtime, where the web
# container starts beside it.
function fastapi_serve_line() {
  local env_file="$1" ;
  echo "$(fastapi_env_line "${env_file}") && until python3 -c 'import socket; socket.create_connection((\"postgres\", 5432), 2)' 2> /dev/null; do sleep 2; done && cd /app/backend && bash scripts/prestart.sh && exec fastapi run --workers ${FASTAPI_WORKERS} --port ${FASTAPI_PORT}" ;
}

# What DDEV is told: the app's service and Postgres's (the plugin's docker-compose.fastapi.yaml), and the mark that makes
# it a project of this builder.
function fastapi_write_ddev_config() {
  local project_path="$1" made="$2" from="${WORKSPACE_SCRIPTS}/plugins/fastapi" ;
  if [ ! -f "${from}/docker-compose.fastapi.yaml" ] ; then
    echo "docker-compose.fastapi.yaml is not in ${from}: install the plugin (plugins.sh --install fastapi)." ;
    return 1 ;
  fi
  mkdir -p "${project_path}/.ddev" || return 1 ;
  cp "${from}/docker-compose.fastapi.yaml" "${project_path}/.ddev/docker-compose.fastapi.yaml" || return 1 ;
  printf 'FASTAPI_POSTGRES_IMAGE=%s\nFASTAPI_WORKERS=%s\n' "${FASTAPI_POSTGRES_IMAGE}" "${FASTAPI_WORKERS}" > "${project_path}/.ddev/.env" || return 1 ;
  cat > "${project_path}/.ddev/config.fastapi.yaml" <<YAMLEOF
# A FastAPI app in this project: its service and Postgres's (docker-compose.fastapi.yaml), their images in .env, the
# app's settings in ../${FASTAPI_OWN}/. Written by the FastAPI builder of the workspace; build again rather than
# editing by hand.
# app: ${made}
YAMLEOF
}

# On another runtime than DDEV (webship/workspace#841): the plugin's claim, the app's own image as the stack, Postgres
# as a service of the project, and the app's server as the web container's own.
function fastapi_runtime_config() {
  local image="$1" ;
  rt_claim fastapi || return 1 ;
  rt_stack image "${image}" || return 1 ;
  rt_service postgres "${FASTAPI_POSTGRES_IMAGE}" --port 5432 --env-file "${FASTAPI_OWN}/postgres.env" --volume /var/lib/postgresql || return 1 ;
  rt_serve "${FASTAPI_PORT}" "$(fastapi_serve_line "/var/www/html/${FASTAPI_OWN}/env")" ;
}

# The app's own image on another runtime, built by the runtime's engine from the app's backend/Dockerfile. The
# Dockerfile names its base images by short names (FROM python:3.14, oven/bun:1), which Docker reads as Docker Hub's;
# Podman resolves a short name only through the registries it is given, and a machine may give it none: its build is
# given Docker Hub as the one to search (.webship-fastapi/registries.conf), for that build alone.
function fastapi_build_image() {
  local project_path="$1" image="$2" engine=docker ;
  [ "$(fastapi_runtime)" = 'podman' ] && engine=podman ;
  echo "Building the app's image (${image}) from its backend/Dockerfile with ${engine}." ;
  if [ "${engine}" = podman ] ; then
    local conf="${project_path}/${FASTAPI_OWN}/registries.conf" ;
    printf '%s\n' "# The registry the short names of the app's Dockerfile are read from, for Podman's build of its image (as Docker" \
      "# reads them). Written by the FastAPI builder of the workspace." 'unqualified-search-registries = ["docker.io"]' > "${conf}" || return 1 ;
    ( cd "${project_path}/${FASTAPI_APP}" && CONTAINERS_REGISTRIES_CONF="${conf}" podman build -t "${image}" -f backend/Dockerfile . < /dev/null ) ;
  else
    ( cd "${project_path}/${FASTAPI_APP}" && docker build -t "${image}" -f backend/Dockerfile . < /dev/null ) ;
  fi
}

# Wait until the app answers its health check (from the web container: the app's service on DDEV, itself elsewhere).
function fastapi_wait() {
  local attempt url ;
  if [ "$(fastapi_runtime)" = 'ddev' ] ; then url="http://fastapi:${FASTAPI_PORT}/api/v1/utils/health-check/" ;
  else url="http://127.0.0.1:${FASTAPI_PORT}/api/v1/utils/health-check/" ; fi
  for attempt in $(seq 1 90) ; do
    if ddev exec "curl -fsS -o /dev/null ${url}" < /dev/null > /dev/null 2>&1 ; then return 0 ; fi
    sleep 2 ;
  done
  echo "The app does not answer its health check (${url})." ;
  return 1 ;
}

# The app in app/: the template at its release, or the folder of a repository. An app of your own must be a FastAPI app
# laid out as the template is: backend/Dockerfile, backend/scripts/prestart.sh.
function fastapi_get_app() {
  local project_path="$1" source="$2" ref="$3" app_path="$4" tmp ;
  local app="${project_path}/${FASTAPI_APP}" ;
  if [ -z "${source}" ] ; then
    echo "Taking the official full-stack FastAPI template ${FASTAPI_TEMPLATE_VERSION}." ;
    git clone --quiet --depth 1 --branch "${FASTAPI_TEMPLATE_VERSION}" "${FASTAPI_TEMPLATE_REPOSITORY}" "${app}" < /dev/null \
      || { echo "The template could not be cloned." ; return 1 ; } ;
  else
    echo "Getting the app: ${source}${ref:+ at ${ref}}${app_path:+, its folder ${app_path}/}" ;
    tmp="$(mktemp -d)" ;
    git clone --quiet --depth 1 ${ref:+--branch "${ref}"} "${source}" "${tmp}/source" < /dev/null \
      || { rm -rf "${tmp}" ; echo "The app could not be cloned from ${source}${ref:+ at ${ref}}." ; return 1 ; } ;
    mkdir -p "${app}" && cp -a "${tmp}/source/${app_path:+${app_path}/}." "${app}/" ;
    rm -rf "${tmp}" ;
  fi
  rm -rf "${app:?}/.git" ;
  if [ ! -f "${app}/backend/Dockerfile" ] || [ ! -f "${app}/backend/scripts/prestart.sh" ] ; then
    echo "${source:-The template}${app_path:+ (${app_path}/)} is not laid out as the full-stack template is (backend/Dockerfile, backend/scripts/prestart.sh): this builder builds and serves such apps." ;
    return 1 ;
  fi
}

# Build an app from nothing: the project and its containers, the app, its image, Postgres, and with --install the app
# served and checked, and its accounts.
function fastapi_build() {
  trim_project_name ;
  local base_url runtime ;
  runtime="$(fastapi_runtime)" ;
  if [ "${RUNTIME:-_none_}" != '_none_' ] && [ "${RUNTIME}" != "${runtime}" ] ; then
    echo "--runtime ${RUNTIME} needs a Webship Workspace with the container runtimes (webship/workspace#694): update the workspace, or build on DDEV." ;
    exit 1 ;
  fi
  case " ${FASTAPI_RUNTIMES} " in
    *" ${runtime} "*) ;;
    *) echo "A FastAPI app builds on DDEV, Docker Compose, Podman and Kubernetes for now (--runtime ddev, docker, podman or kubernetes), not on ${runtime}: that runtime is not proven for it yet. Nothing was changed." ; exit 1 ;;
  esac
  if ! declare -F export_project_db > /dev/null ; then
    echo "A FastAPI app keeps a Postgres of its own, which the row's Backup and Restore reach through the core's database hook: it needs Webship Workspace 1.0.42 or newer (webship/workspace#937). Update the workspace. Nothing was changed." ;
    exit 1 ;
  fi
  if [ "${runtime}" != 'ddev' ] && ! declare -f rt_service > /dev/null ; then
    echo "FastAPI on ${runtime} needs a Webship Workspace whose runtimes take an application's own image and services (webship/workspace#841, #900): update the workspace, or build on DDEV." ;
    exit 1 ;
  fi
  local source="${SOURCE:-${app_source:-}}" ;
  local ref="${REF:-${app_source_ref:-}}" ;
  local app_path="${APP_PATH:-${app_source_path:-}}" ;
  if [ -n "${app_path}" ] && [ -z "${source}" ] ; then
    echo "--path names a folder of the repository given with --source: give --source too. Nothing was changed." ;
    exit 1 ;
  fi
  if [[ "${app_path}" == /* ]] || [[ "/${app_path}/" == */../* ]] || [[ "${app_path}" == *"'"* ]] || [[ "${source}${ref}" == *"'"* ]] ; then
    echo "--source, --ref and --path take a repository, a branch or tag, and a folder inside the repository. Nothing was changed." ;
    exit 1 ;
  fi
  if [ ${#PROJECT_NAME} -gt 40 ] || ! [[ "${PROJECT_NAME}" =~ ^[a-z0-9][a-z0-9-]*$ ]] ; then
    echo "The project name ${PROJECT_NAME} must be small letters, digits and dashes (its address and its containers take it). Nothing was changed." ;
    exit 1 ;
  fi
  local project_path="${WORKSPACE_ROOT}/${doc_name}/${PROJECT_NAME}" ;
  local made ;
  if [ -n "${source}" ] ; then made="${source}${ref:+ (${ref})}${app_path:+, ${app_path}/}" ;
  else made="the official full-stack FastAPI template ${FASTAPI_TEMPLATE_VERSION}" ; fi

  cd ${WORKSPACE_ROOT}/${doc_name} || exit 1 ;

  # A project of the same name goes first, with its containers and its Postgres volume.
  drop_database ;
  rm -rf "${PROJECT_NAME:?}" ;
  mkdir -p "${PROJECT_NAME}" ;
  cd "${project_path}" || exit 1 ;

  fastapi_get_app "${project_path}" "${source}" "${ref}" "${app_path}" || exit 1 ;

  # A generic project without DDEV's database: the app and its Postgres are its own.
  ddev config --project-type=generic --webserver-type=generic --docroot="" --project-name=${PROJECT_NAME} \
    --omit-containers=db --auto < /dev/null || exit 1 ;
  # The address is the runtime's to say, once the project is configured: never a written ddev.site. The settings come
  # before the services: on Kubernetes, Postgres's env file is read when the project's manifests are written.
  base_url="$(fastapi_url)" ;
  fastapi_write_env "${project_path}" "${base_url}" || exit 1 ;
  local image="fastapi-${PROJECT_NAME}:app" ;
  if [ "${runtime}" == 'ddev' ] ; then
    fastapi_write_ddev_config "${project_path}" "${made}" || exit 1 ;
  else
    fastapi_build_image "${project_path}" "${image}" || { echo "The app's image could not be built." ; exit 1 ; } ;
    fastapi_runtime_config "${image}" || { echo "The app's stack could not be written through the runtime layer." ; exit 1 ; } ;
  fi

  if [ "${INSTALL}" == 'yes' ] || [ "${ADD_USERS}" == 'yes' ] ; then
    echo "Starting the project: the app's image${runtime:+ on ${runtime}}, and Postgres 18." ;
    ddev_up start -y < /dev/null || exit 1 ;
    fastapi_wait || exit 1 ;
    if [ "${ADD_USERS}" == 'yes' ] ; then
      set_fastapi_users ;
      add_fastapi_users || exit 1 ;
    fi
    echo "${doc_name} ${PROJECT_NAME} is served: the FastAPI app in ${FASTAPI_APP}/ (${made}), on Postgres 18." ;
    echo "Go to ${base_url}" ;
  else
    echo "${doc_name} ${PROJECT_NAME} is ready: the FastAPI app in ${FASTAPI_APP}/ (${made})." ;
    if [ "${runtime}" = 'ddev' ] ; then
      echo "Serve it with: cd ${PROJECT_NAME} && ddev start   (or build with --install)" ;
    else
      echo "Serve it with Start in its row of the dashboard (or build with --install)" ;
    fi
  fi

  if [ "${LAUNCH}" == 'yes' ] ; then
    ddev launch ;
  fi

  cd ${WORKSPACE_ROOT}/${doc_name};
}

# Into the project of this builder named PROJECT_NAME, from its folder.
function fastapi_enter_project() {
  local project_path="${WORKSPACE_ROOT}/${doc_name}/${PROJECT_NAME}" ;
  if ! fastapi_is_project "${project_path}" ; then
    echo "${doc_name}/${PROJECT_NAME} is not a project of the FastAPI builder." ;
    return 1 ;
  fi
  cd "${project_path}" || return 1 ;
}

# A request to the app's API from inside the app's container, through Python (the app's own): METHOD PATH, the body (JSON)
# and the bearer token on the input as one JSON object; the answer's status and body on the output.
function fastapi_api() {
  ddev exec -s "$(fastapi_app_service)" -d / "python3 -c \"
import json, sys, urllib.request
r = json.load(sys.stdin)
data = json.dumps(r['body']).encode() if r.get('body') is not None else (r['form'].encode() if r.get('form') else None)
req = urllib.request.Request('http://127.0.0.1:${FASTAPI_PORT}' + r['path'], data=data, method=r['method'])
if r.get('body') is not None: req.add_header('Content-Type', 'application/json')
if r.get('form'): req.add_header('Content-Type', 'application/x-www-form-urlencoded')
if r.get('token'): req.add_header('Authorization', 'Bearer ' + r['token'])
try:
    with urllib.request.urlopen(req, timeout=30) as a: print(a.status); print(a.read().decode())
except urllib.error.HTTPError as e: print(e.code); print(e.read().decode())
\"" ;
}

# The first superuser's token, from the app's token address.
function fastapi_token() {
  local answer ;
  set_fastapi_users ;
  answer="$(python3 -c 'import json, sys, urllib.parse; print(json.dumps({"method": "POST", "path": "/api/v1/login/access-token", "form": urllib.parse.urlencode({"username": sys.argv[1], "password": sys.argv[2]})}))' "${user_admin_mail}" "${user_admin_password}" | fastapi_api)" ;
  [ "$(echo "${answer}" | head -1)" = '200' ] || { echo "The first superuser could not sign in: ${answer}" >&2 ; return 1 ; } ;
  echo "${answer}" | tail -n +2 | python3 -c 'import json, sys; print(json.load(sys.stdin)["access_token"])' ;
}

# Make the default accounts through the app's API, as its first superuser: the first superuser is the app's own (its
# prestart makes it), the others are made active with their password, or made active again when they are there.
function add_fastapi_users() {
  fastapi_enter_project || return 1 ;
  local token user user_name user_mail user_password user_fullname user_role body answer status=0 ;
  token="$(fastapi_token)" || { cd ${WORKSPACE_ROOT}/${doc_name} ; return 1 ; } ;
  for user in "${users[@]}" ; do
    user_name="user_${user}_name"; user_mail="user_${user}_mail"; user_password="user_${user}_password"; user_fullname="user_${user}_fullname"; user_role="user_${user}_role";
    echo " ---------------------------------------------------------------- ";
    echo "      User name: ${!user_name}";
    echo "      User mail: ${!user_mail}";
    echo "  User password: ${!user_password}";
    echo "      User role: ${!user_role}";
    echo " ================================================================= ";
    [ "${!user_role}" = 'superuser' ] && continue ;
    body="$(python3 -c 'import json, sys; print(json.dumps({"method": "POST", "path": "/api/v1/users/", "token": sys.argv[1], "body": {"email": sys.argv[2], "password": sys.argv[3], "full_name": sys.argv[4] or None, "is_active": True, "is_superuser": False}}))' "${token}" "${!user_mail}" "${!user_password}" "${!user_fullname}")" ;
    answer="$(echo "${body}" | fastapi_api)" ;
    case "$(echo "${answer}" | head -1)" in
      200) echo "  made." ;;
      400) echo "  there already." ;;
      *) echo "  not made: ${answer}" ; status=1 ;;
    esac
  done
  cd ${WORKSPACE_ROOT}/${doc_name};
  return ${status} ;
}

# Keep the default accounts from signing in (made inactive through the app's API; their items stay), never the first
# superuser.
function cancel_fastapi_users() {
  fastapi_enter_project || return 1 ;
  local token user user_mail user_role list id status=0 ;
  token="$(fastapi_token)" || { cd ${WORKSPACE_ROOT}/${doc_name} ; return 1 ; } ;
  list="$(python3 -c 'import json, sys; print(json.dumps({"method": "GET", "path": "/api/v1/users/?skip=0&limit=10000", "token": sys.argv[1]}))' "${token}" | fastapi_api | tail -n +2)" ;
  for user in "${users[@]}" ; do
    user_mail="user_${user}_mail"; user_role="user_${user}_role";
    [ "${!user_role}" = 'superuser' ] && continue ;
    id="$(echo "${list}" | python3 -c 'import json, sys; d = json.load(sys.stdin); print(next((u["id"] for u in d.get("data", []) if u["email"] == sys.argv[1]), ""))' "${!user_mail}")" ;
    [ -n "${id}" ] || { echo "  ${!user_mail}: not there." ; continue ; } ;
    if [ "$(python3 -c 'import json, sys; print(json.dumps({"method": "PATCH", "path": "/api/v1/users/" + sys.argv[2], "token": sys.argv[1], "body": {"is_active": False}}))' "${token}" "${id}" | fastapi_api | head -1)" = '200' ] ; then
      echo "  ${!user_mail}: made inactive." ;
    else
      echo "  ${!user_mail}: could not be made inactive." ; status=1 ;
    fi
  done
  cd ${WORKSPACE_ROOT}/${doc_name};
  return ${status} ;
}

# ---------------------------------------------------------------------------------------------------------------------
# The database hook (webship/workspace#937): the row's Backup and Restore ask these first, on every runtime.
# ---------------------------------------------------------------------------------------------------------------------

# The extension of the plugin's own dumps.
function fastapi_db_extension() {
  echo "${FASTAPI_DB_EXTENSION}" ;
}

# Write the app's database to <file>, in the project's folder: pg_dump's custom format, or a gzipped SQL dump for a file
# named *.sql.gz (what the safety dump before a remove and a clone ask for).
function fastapi_export_db() {
  local file="$1" ;
  case "${file}" in
    *.sql.gz)
      fastapi_pg pg_dump -U postgres --no-owner --no-privileges app < /dev/null | gzip > "${file}" ;
      [ "${PIPESTATUS[0]}" -eq 0 ] && gunzip -c "${file}" 2> /dev/null | tail -c 200 | grep -q 'PostgreSQL database dump complete' ;;
    *)
      fastapi_pg pg_dump -U postgres -Fc --no-owner --no-privileges app < /dev/null > "${file}" \
        && [ "$(head -c 5 "${file}")" = 'PGDMP' ] ;;
  esac || {
    echo "The database of $(basename "$(pwd)") could not be dumped to ${file##*/}." >&2 ;
    rm -f "${file}" ;
    return 1 ;
  }
  echo "The database of $(basename "$(pwd)") (Postgres 18, app) is in ${file}." ;
}

# The script that starts the app's workers again, run in the app's container: FastAPI's server (uvicorn, with more than
# one worker: FASTAPI_WORKERS) restarts its workers one by one on SIGHUP, and the script waits until the old ones are
# gone. The server is found by its command line, `…bin/fastapi run …`, which the script's own command line cannot
# match (its text has a backslash before each space). PROC is /proc in the container; the plugin's tests give it a
# folder of their own.
function fastapi_reload_script() {
  cat <<'SHEOF'
proc="${PROC:-/proc}" ; master="" ; old=""
for p in "$proc"/[0-9]* ; do
  case "$(tr "\0" " " 2> /dev/null < "$p/cmdline")" in
    *bin/fastapi\ run\ *) n="${p##*/}" ; if [ -z "$master" ] || [ "$n" -lt "$master" ] ; then master="$n" ; fi ;;
  esac
done
[ -n "$master" ] || exit 1
for p in "$proc"/[0-9]* ; do
  ppid="" ; while read -r k v _ ; do if [ "$k" = "PPid:" ] ; then ppid="$v" ; break ; fi ; done 2> /dev/null < "$p/status"
  [ "$ppid" = "$master" ] || continue
  case "$(tr "\0" " " 2> /dev/null < "$p/cmdline")" in *spawn_main*) old="$old ${p##*/}" ;; esac
done
kill -HUP "$master" || exit 1
for i in $(seq 1 120) ; do
  left="" ; for o in $old ; do if [ -d "$proc/$o" ] ; then left=1 ; fi ; done
  [ -z "$left" ] && exit 0
  sleep 0.5
done
exit 1
SHEOF
}

# The app's workers start again with new connections to its database, and the app answers again: after a restore, the
# connections its workers held were to the database that stepped aside.
function fastapi_reload_app() {
  ddev exec -s "$(fastapi_app_service)" -d / "$(fastapi_reload_script)" < /dev/null > /dev/null 2>&1 \
    || echo "The app's workers could not be started again: restart the project if the app does not answer." >&2 ;
  fastapi_wait > /dev/null ;
}

# Put <file> back as the app's database: checked first (a custom-format dump pg_restore can list, or a gzipped SQL dump
# that ends where pg_dump ends it), into a database of its own, and only a whole restore takes the place of app. The
# app's connections go while the restored database takes its name, and its workers start again with new ones.
function fastapi_import_db() {
  local file="$1" kind project ;
  project="$(basename "$(pwd)")" ;
  if [ "$(head -c 5 "${file}" 2> /dev/null)" = 'PGDMP' ] ; then
    kind=custom ;
    fastapi_pg pg_restore --list < "${file}" > /dev/null 2>&1 || { echo "${file##*/} is not a whole dump: pg_restore cannot read its list. Nothing was changed." >&2 ; return 1 ; } ;
  elif gzip -t "${file}" 2> /dev/null && gunzip -c "${file}" | head -c 4096 | grep -q 'PostgreSQL database dump' \
       && gunzip -c "${file}" | tail -c 200 | grep -q 'PostgreSQL database dump complete' ; then
    kind=sql ;
  else
    echo "${file##*/} is not a dump of a Postgres database (pg_dump's custom format, or its gzipped SQL). Nothing was changed." >&2 ;
    return 1 ;
  fi
  echo "This replaces the database of ${project} (Postgres 18, app) with ${file##*/}." ;
  fastapi_pg psql -U postgres -d postgres -v ON_ERROR_STOP=1 -q -c 'SET client_min_messages = warning' \
    -c 'DROP DATABASE IF EXISTS app_restore WITH (FORCE)' -c 'CREATE DATABASE app_restore' < /dev/null || return 1 ;
  if [ "${kind}" = custom ] ; then
    fastapi_pg pg_restore -U postgres -d app_restore --no-owner --no-privileges --exit-on-error < "${file}" ;
  else
    gunzip -c "${file}" | fastapi_pg psql -U postgres -d app_restore -v ON_ERROR_STOP=1 -q > /dev/null ;
  fi || {
    fastapi_pg psql -U postgres -d postgres -q -c 'SET client_min_messages = warning' -c 'DROP DATABASE IF EXISTS app_restore WITH (FORCE)' < /dev/null > /dev/null ;
    echo "${file##*/} did not go in whole. The database of ${project} is as it was." >&2 ;
    return 1 ;
  }
  # The swap: the old database takes no new connections and its open ones go (each waited for), then in one transaction
  # it steps aside and the restored one takes its name. On a failure the old one is open again, under its own name.
  if ! fastapi_pg psql -U postgres -d postgres -v ON_ERROR_STOP=1 -q -c 'SET client_min_messages = warning' \
      -c 'DROP DATABASE IF EXISTS app_before_restore WITH (FORCE)' -c 'ALTER DATABASE app WITH ALLOW_CONNECTIONS false' \
      -c "SELECT pg_terminate_backend(pid, 5000) FROM pg_stat_activity WHERE datname = 'app' AND pid <> pg_backend_pid()" \
      -c 'BEGIN' -c 'ALTER DATABASE app RENAME TO app_before_restore' -c 'ALTER DATABASE app_restore RENAME TO app' -c 'COMMIT' \
      < /dev/null > /dev/null ; then
    fastapi_pg psql -U postgres -d postgres -q -c 'SET client_min_messages = warning' -c 'ALTER DATABASE app WITH ALLOW_CONNECTIONS true' \
      -c 'DROP DATABASE IF EXISTS app_restore WITH (FORCE)' < /dev/null > /dev/null 2>&1 ;
    echo "The restored database could not take the place of app: the database of ${project} is as it was." >&2 ;
    return 1 ;
  fi
  fastapi_pg psql -U postgres -d postgres -q -c 'DROP DATABASE app_before_restore WITH (FORCE)' < /dev/null > /dev/null ;
  fastapi_reload_app ;
  echo "The database of ${project} is now ${file##*/}." ;
}

# ---------------------------------------------------------------------------------------------------------------------
# The step pack in the testing stack
# ---------------------------------------------------------------------------------------------------------------------

# The step pack in the testing stack of an app of this builder. The core's testing_configure calls this in the project
# folder once webship-js is scaffolded and before the dependencies are installed; for a project that is not an app of
# this builder it changes nothing.
#
# It adds the pack to package.json; lists its step definitions in cucumber.js after webship-js's own; gives the suite
# the app's address where the scaffold has its placeholder; adds the accounts
# the scenarios name (worldParameters.users: admin and user, their passwords from the environment, the workspace's by
# default) and, for the template, the one known error its pages log (the 404 of /vite.svg, by its address alone); and
# writes a first feature for the template when the project has none of its own. Every part is skipped when it is
# already done, so a second run adds what the first missed and never resets a suite.
function testing_configure_fastapi() {
  local project_path="$1";
  fastapi_is_project "${project_path}" || return 0 ;
  if [ ! -f "${project_path}/cucumber.js" ] || [ ! -f "${project_path}/package.json" ] ; then
    echo "  FastAPI: cucumber.js is not here yet — run the testing setup again once webship-js is scaffolded." ;
    return 1 ;
  fi
  local template='no' ;
  [ -f "${project_path}/${FASTAPI_APP}/frontend/src/routes/login.tsx" ] && grep -q 'app.frontend("/"' "${project_path}/${FASTAPI_APP}/backend/app/main.py" 2> /dev/null && template='yes' ;

  # The app's address, as its runtime gives it (https://<name>.ddev.site on DDEV).
  local address ;
  address="$(cd "${project_path}" && PROJECT_NAME="${PROJECT_NAME:-$(basename "${project_path}")}" fastapi_url)" ;

  echo "Adding the FastAPI step pack (${FASTAPI_STEPS_PACKAGE} ${FASTAPI_STEPS_VERSION}).";

  python3 - "${project_path}" "${FASTAPI_STEPS_PACKAGE}" "${FASTAPI_STEPS_VERSION}" "${template}" "${address}" <<'PYEOF' || return 1
import json, re, sys

project, pack, version, template, address = sys.argv[1:6]

# package.json: the pack as a dev dependency, at the release line this plugin was proven on.
pkg_file = project + '/package.json'
pkg = json.load(open(pkg_file))
if pack not in pkg.get('dependencies', {}) and pack not in pkg.get('devDependencies', {}):
    pkg.setdefault('devDependencies', {})[pack] = version
    open(pkg_file, 'w').write(json.dumps(pkg, indent=2) + '\n')
    print('  package.json: %s %s' % (pack, version))

cucumber_file = project + '/cucumber.js'
src = open(cucumber_file).read()
before = src

# The pack's step definitions after webship-js's own.
if ('node_modules/%s/' % pack) not in src:
    line = "'node_modules/%s/tests/step-definitions/*.js'," % pack
    core = re.search(r"^([ \t]*)'node_modules/webship-js/tests/step-definitions/[^']*',.*$", src, re.M)
    opening = re.search(r"^([ \t]*)require:[ \t]*\[[ \t]*$", src, re.M)
    if core:
        src = src[:core.end()] + '\n' + core.group(1) + line + src[core.end():]
    elif opening:
        src = src[:opening.end()] + '\n' + opening.group(1) + '  ' + line + src[opening.end():]
    else:
        sys.exit("  cucumber.js has no require list this can add to. Add this line to it:\n    " + line)
    print('  cucumber.js: the step definitions of %s' % pack)

# The accounts the scenarios name, in worldParameters (their passwords from the environment).
if not re.search(r"^\s*users:\s*\{", src, re.M):
    users = [
        "users: {",
        "  admin: { username: process.env.FASTAPI_ADMIN_USERNAME || 'admin@example.com', password: process.env.FASTAPI_ADMIN_PASSWORD || 'dD.123123ddd' },",
        "  user: { username: process.env.FASTAPI_USER_USERNAME || 'user@example.com', password: process.env.FASTAPI_USER_PASSWORD || 'dD.123123ddd' },",
        "},",
    ]
    wp = re.search(r"^([ \t]*)worldParameters:[ \t]*\{[ \t]*$", src, re.M)
    if wp:
        indent = wp.group(1) + '  '
        src = src[:wp.end()] + '\n' + '\n'.join(indent + line for line in users) + src[wp.end():]
        print('  cucumber.js: the accounts admin and user (FASTAPI_ADMIN_PASSWORD, FASTAPI_USER_PASSWORD)')

# The template's one known error (its index.html links /vite.svg, which its build does not ship), let through by its
# address alone (webship-js 2.0.19 reads a console message's address); every other browser error still counts.
if template == 'yes' and 'vite\\\\.svg' not in src and 'vite\\.svg' not in src:
    pattern = "'^Failed to load resource: the server responded with a status of 404 \\\\(Not Found\\\\) @ https?://[^/]+/vite\\\\.svg$'"
    empty = re.search(r"(\bignore:\s*)(''|\"\"|null)", src)
    block = re.search(r"^([ \t]*)javascript:[ \t]*\{[ \t]*$", src, re.M)
    wp = re.search(r"^([ \t]*)worldParameters:[ \t]*\{[ \t]*$", src, re.M)
    done = True
    if empty:
        src = src[:empty.start(2)] + pattern + src[empty.end(2):]
    elif block:
        src = src[:block.end()] + '\n' + block.group(1) + '  ignore: ' + pattern + ',' + src[block.end():]
    elif wp:
        indent = wp.group(1) + '  '
        src = (src[:wp.end()] + '\n' + indent + "// The template's index.html links /vite.svg, which its build does not ship: that one 404 by its address." +
               '\n' + indent + 'javascript: { ignore: ' + pattern + ' },' + src[wp.end():])
    else:
        done = False
    if done:
        print('  cucumber.js: the 404 of /vite.svg let through by its address (webship-js 2.0.19)')

# The address the suite opens when LAUNCH_URL is not set. On DDEV the router sends the project's address to the app's
# own service, so DDEV gives the web container no primary URL, and the scaffold's placeholder would be the suite's
# address: it becomes the app's. On another runtime the tests' container is given LAUNCH_URL, which still wins.
placeholder = "process.env.LAUNCH_URL || 'http://localhost:8080'"
if address and placeholder in src:
    src = src.replace(placeholder, "process.env.LAUNCH_URL || '%s'" % address)
    print('  cucumber.js: the address of the app (%s)' % address)

if src != before:
    open(cucumber_file, 'w').write(src)
PYEOF

  # A first feature, for the template only (an app of your own has its own pages), when the project has none yet.
  local feature="${WORKSPACE_SCRIPTS}/plugins/fastapi/site.feature" ;
  if [ -f "${feature}" ] && [ ! -f "${project_path}/tests/features/site.feature" ] ; then
    if [ "${template}" = 'yes' ] ; then
      mkdir -p "${project_path}/tests/features" && cp "${feature}" "${project_path}/tests/features/site.feature" \
        && echo "  tests/features/site.feature: a first feature for the template" ;
    else
      echo "  FastAPI: the app is not the full-stack template, so no first feature is written: write one from what its pages and its API show." ;
    fi
  fi
}
