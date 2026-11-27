Feature: The FastAPI app of this project
  The official full-stack template: its API (signed in through its own token address, its refusals field by field, its
  documented schema), its interactive docs, and its front end as it uses the API. Written by the FastAPI plugin's
  testing setup as a first feature; make it this app's own.

  Scenario: Signed in, the API knows the account
    Given the API base URL is "/"
    And I am signed in to the API as "admin"
    When I send a GET request to "/api/v1/users/me"
    Then the API response code should be 200
    And the API's answer should match its documented schema

  Scenario: A sign-up refused field by field
    Given the API base URL is "/"
    When I send a POST request to "/api/v1/users/signup" with body:
      """
      {"email": "not-an-address", "password": "short"}
      """
    Then the API response code should be 422
    And the API should have refused "password" with "at least 8 characters"

  @needs-javascript
  Scenario: The docs list the operations of the schema
    When I open the API docs
    Then the API docs should list "POST /api/v1/login/access-token"

  @needs-javascript
  Scenario: Signed in, the app reads the account from the API
    Given I am signed in to the app as "user"
    Then the app should have called "GET /api/v1/users/me"
    And the app's call should have been accepted

  @needs-javascript
  Scenario: An address the app does not know
    Given I am on "/does-not-exist"
    Then the app should show its not-found page
