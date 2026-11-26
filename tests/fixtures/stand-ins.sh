# Stand-ins for the commands the FastAPI plugin's functions run, for its tests: ddev (and what it runs in the app's and
# Postgres's containers), git, docker, podman and the core's helpers, each call written to $LOG. Nothing here reaches
# a container or the network.
#   FAIL          clone | dump | short | list | restore | swap: that step fails (short: a dump cut before its end)
#   LAYOUT        none: the cloned app is not laid out as the full-stack template is
#   APP_DIR       the folder of the app in a cloned repository (--path)
#   USERS_ANSWER  the status the app's API answers when an account is made (200 made, 400 there already)

trim_project_name() { :; }
drop_database() { echo "drop_database" >> "${LOG}" ; }
ddev_up() { ddev "$@" ; }
# The core's database hook (webship/workspace#937, core 1.0.42): its presence is what the builder asks for.
export_project_db() { echo "export_project_db $*" >> "${LOG}" ; }

ddev() {
  echo "ddev $*" >> "${LOG}" ;
  case "$*" in
    *"pg_dump -U postgres -Fc"*) [ "${FAIL:-}" = dump ] && return 1 ; printf 'PGDMP\001\016fake' ;;
    *"pg_dump -U postgres --no-owner"*)
      printf -- '--\n-- PostgreSQL database dump\n--\n\nCREATE TABLE public.item (id uuid);\n' ;
      [ "${FAIL:-}" = short ] || printf -- '\n--\n-- PostgreSQL database dump complete\n--\n\n\\unrestrict k1\n\n' ;;
    *"pg_restore --list"*) cat > /dev/null ; [ "${FAIL:-}" = list ] && return 1 ;;
    *"pg_restore -U postgres -d app_restore"*|*"psql -U postgres -d app_restore"*) cat > /dev/null ; [ "${FAIL:-}" = restore ] && return 1 ;;
    *"ALTER DATABASE app RENAME TO app_before_restore"*) [ "${FAIL:-}" = swap ] && return 1 ;;
    *"python3 -c"*)
      local in ; in="$(cat)" ;
      case "${in}" in
        *'"/api/v1/login/access-token"'*) printf '200\n{"access_token": "t0k", "token_type": "bearer"}\n' ;;
        *'"POST", "path": "/api/v1/users/"'*) printf '%s\n{}\n' "${USERS_ANSWER:-200}" ;;
        *'"GET", "path": "/api/v1/users/'*) printf '200\n{"data": [{"id": "u-1", "email": "user@example.com"}], "count": 1}\n' ;;
        *'"PATCH", "path": "/api/v1/users/u-1"'*) printf '200\n{}\n' ;;
      esac ;;
  esac
  return 0 ;
}

git() {
  echo "git $*" >> "${LOG}" ;
  [ "$1" = clone ] || return 0 ;
  [ "${FAIL:-}" = clone ] && return 128 ;
  local dest="${!#}" app ;
  app="${dest}${APP_DIR:+/${APP_DIR}}" ;
  mkdir -p "${dest}/.git" "${app}/backend/app" "${app}/backend/scripts" "${app}/frontend/src/routes" ;
  if [ "${LAYOUT:-}" != none ] ; then
    printf 'FROM python:3.14\n' > "${app}/backend/Dockerfile" ;
    printf 'alembic upgrade head\n' > "${app}/backend/scripts/prestart.sh" ;
    printf 'app.frontend("/", directory=FRONTEND_DIR)\n' > "${app}/backend/app/main.py" ;
    printf 'export const Route = {}\n' > "${app}/frontend/src/routes/login.tsx" ;
  fi
}

docker() { echo "docker $*" >> "${LOG}" ; return 0 ; }
podman() { echo "podman $*" >> "${LOG}" ; return 0 ; }
