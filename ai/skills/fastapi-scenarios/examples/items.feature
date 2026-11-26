@needs-javascript
Feature: Items in the app's front end
  The front end calls the API from the page and says what happened in its messages.

  @removes-test-content
  Scenario: An item added through the app
    Given I am signed in to the app as "user"
    And I am on "/items"
    And I wait for the app's API calls to finish
    When I press "Add Item"
    And I fill in "Title" with "Webship test item"
    And I press "Save"
    Then the app should have called "POST /api/v1/items/"
    And the app's call should have been accepted
    And the app should show the message "Item created successfully"
    And I wait for the app's messages to go

  Scenario: A title the app refuses before it sends anything
    Given I am signed in to the app as "user"
    And I am on "/items"
    And I wait for the app's API calls to finish
    When I press "Add Item"
    And I press "Save"
    Then the "Title" field should say "Title is required"
