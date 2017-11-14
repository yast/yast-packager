
Feature: Test the repository manager

  Scenario: Adding a new repository
    Given the dialog heading should be "Configured Software Repositories"
    And I click button "Add"
    Then the dialog heading should be "Add On Product"

    When I click button "Next"
    Then the dialog heading should be "Repository URL"

    When I enter "Tumbleweed OSS" into input field "Repository Name"
    And I enter "http://download.opensuse.org/tumbleweed/repo/oss/" into input field "URL"
    And I click button "Next"
    Then the dialog heading should be "Tumbleweed OSS License Agreement"

    When I click button "Next"
    Then the dialog heading should be "Configured Software Repositories"
  
