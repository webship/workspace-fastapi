@needs-javascript
Feature: The interactive docs
  FastAPI draws them from the schema: they list the operations, sign in through their Authorize dialog, and try one out.

  Scenario: Authorized, the docs read the account
    When I open the API docs
    And I authorize the API docs as "admin"
    And I try out "GET /api/v1/users/me" in the API docs
    Then the API docs should show the answer 200

  # The API refuses a short password (a 422), which the browser logs as a console error: warn, so only the
  # assertion under test can fail the scenario.
  @js-warn
  Scenario: Tried out with a short password, the docs show the refusal
    When I open the API docs
    And I try out "POST /api/v1/users/signup" in the API docs with:
      """
      {"email": "webship.test.docs@example.com", "password": "short"}
      """
    Then the API docs should show the answer 422 saying "String should have at least 8 characters"
