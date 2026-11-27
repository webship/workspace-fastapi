#!/usr/bin/env bash

argparse "$@" <<ARGEOF || exit 1
parser.add_argument('PROJECT_NAME',
                    help='The name of the project: its folder, and its project on the container runtime.')
parser.add_argument('--runtime',
                    dest='RUNTIME',
                    default="_none_",
                    choices=['ddev', 'docker', 'podman', 'kubernetes'],
                    help='The container runtime to build on: ddev (the default, or container.runtime of settings.yml), docker (Docker Compose), podman or kubernetes.')
parser.add_argument('-s', '--source',
                    default="${app_source}",
                    help="A git repository of a FastAPI app laid out as the full-stack template is (backend/Dockerfile, backend/scripts/prestart.sh) to build instead of the template; empty means the template. [default %(default)s]")
parser.add_argument('-r', '--ref',
                    default="${app_source_ref}",
                    help='A branch or a tag of that repository; empty means its default branch. Example: --ref main [default %(default)s]')
parser.add_argument('-p', '--path',
                    dest='APP_PATH',
                    default="${app_source_path}",
                    help='The folder of the app in that repository, for a repository of several apps; empty means its root. Example: --path services/api [default %(default)s]')
parser.add_argument('-i', '--install',
                    action='store_true',
                    default=False,
                    help="Start the app (its image, its Postgres, its migrations and first superuser) and check that it answers its health check at its address: https://<name>.ddev.site on DDEV, a port of this machine on Docker Compose and Podman, a port of the node on Kubernetes.")
parser.add_argument('-a', '--add-users',
                    action='store_true',
                    default=False,
                    help="Make the default accounts too, through the app's API: the first superuser admin@example.com is the app's own, the normal account user@example.com is made (cmd-tools-add-users.sh <name> fastapi does it later).")
parser.add_argument('-l', '--launch',
                    action='store_true',
                    default=False,
                    help='Open the app in a browser when it is ready.')
ARGEOF
