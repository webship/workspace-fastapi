Feature: The API of the app
  Its answers in JSON, its token, its refusals field by field, and the schema it documents. No browser needed.

  Background:
    Given the API base URL is "/"

  Scenario: Signed in, the API knows the account
    Given I am signed in to the API as "user"
    When I send a GET request to "/api/v1/users/me"
    Then the API response code should be 200
    And the API's answer should match its documented schema

  Scenario: A sign-up with no address and a short password, refused field by field
    When I send a POST request to "/api/v1/users/signup" with body:
      """
      {"email": "not-an-address", "password": "short"}
      """
    Then the API response code should be 422
    And the API should have refused "email" with "not a valid email address"
    And the API should have refused "password" with "at least 8 characters"

  Scenario: Without a token the API says why it refuses
    When I send a GET request to "/api/v1/users/me"
    Then the API response code should be 401
    And the API should have said "Not authenticated"

  Scenario: The schema documents the operations
    Then the API should document "POST /api/v1/login/access-token"
    And the API should document "GET /api/v1/items/{id}"
