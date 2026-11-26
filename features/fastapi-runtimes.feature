Feature: A FastAPI app on Docker Compose, Podman and Kubernetes
  The builder builds on DDEV by default, and with --runtime on Docker Compose, Podman or a Kubernetes cluster. An app
  built there has the row a DDEV project has: its state, its own address and the runtime's menu, and the app's own
  image serves it, on its own Postgres.

  # Each scenario drives a real app of that runtime, built with cmd-fastapi-project.sh --runtime: the first running one
  # the workspace holds. Without one it is skipped, with the reason. In the plugin's CI the Docker Compose app is the
  # one the manifest's featuresSite builds: the full-stack template, ci-fastapi.

  @needs-runtime-docker @needs-platform-fastapi
  Scenario: A FastAPI app built on Docker Compose runs at its own address, with the DOCKER menu
    Given I am on the folder of the "docker" site
     Then the row of the "docker" site should show "Running"
      And the row of the "docker" site should link to the address of its runtime
      And the address of the "docker" site should answer
      And the row of the "docker" site should carry the "DOCKER" menu and no DDEV menu

  # The app answers its health check from its own API, which reads nothing but itself, and its front end is drawn in
  # the browser from the build the app's image carries.
  @needs-runtime-docker @needs-platform-fastapi
  Scenario: The app on Docker Compose is the template's image: its API and its front end
    Given I am on the folder of the "docker" site
     When I open "/login" on the "docker" site
     Then "h1" should contain text "Login to your account" within 30 seconds

  @needs-runtime-podman @needs-platform-fastapi
  Scenario: A FastAPI app built on Podman runs at its own address, with the PODMAN menu
    Given I am on the folder of the "podman" site
     Then the row of the "podman" site should show "Running"
      And the row of the "podman" site should link to the address of its runtime
      And the address of the "podman" site should answer
      And the row of the "podman" site should carry the "PODMAN" menu and no DDEV menu

  @needs-runtime-podman @needs-platform-fastapi
  Scenario: The app on Podman is the template's image: its API and its front end
    Given I am on the folder of the "podman" site
     When I open "/login" on the "podman" site
     Then "h1" should contain text "Login to your account" within 30 seconds

  @needs-runtime-kubernetes @needs-platform-fastapi
  Scenario: A FastAPI app built on Kubernetes runs at the address of its node, with the K8S menu
    Given I am on the folder of the "kubernetes" site
     Then the row of the "kubernetes" site should show "Running"
      And the row of the "kubernetes" site should link to the address of its runtime
      And the address of the "kubernetes" site should answer
      And the row of the "kubernetes" site should carry the "K8S" menu and no DDEV menu

  @needs-runtime-kubernetes @needs-platform-fastapi
  Scenario: The app on Kubernetes is the template's image: its API and its front end
    Given I am on the folder of the "kubernetes" site
     When I open "/login" on the "kubernetes" site
     Then "h1" should contain text "Login to your account" within 30 seconds
