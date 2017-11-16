
Feature: To be able to install the 3rd party packages
    I must be able to add a new package repository to the package management.

  Background:
    # make sure the tested repository does not already exist
    When I run `zypper lr -u `
    Then the output should not contain "https://download.opensuse.org/tumbleweed/repo/oss/"

  Scenario: Adding a new repository
    Given I start the "/usr/sbin/yast2 repositories" application
    Then the dialog heading should be "Configured Software Repositories"

    When I click button "Add"
    Then the dialog heading should be "Add On Product"

    When I click button "Next"
    Then the dialog heading should be "Repository URL"

    When I enter "Tumbleweed OSS" into input field "Repository Name"
    And I enter "https://download.opensuse.org/tumbleweed/repo/oss/" into input field "URL"
    And I click button "Next"
    Then the dialog heading should be "Tumbleweed OSS License Agreement"

    When I click button "Next"
    Then the dialog heading should be "Configured Software Repositories"

    When I click button "Cancel"
    Then a popup should be displayed
    Then the "Abort repository configuration?" label should be displayed
    Then I click button "Yes"
    And I wait for the application to finish

    # verify that the tested repository was NOT added
    When I run `zypper lr -u `
    Then the output should not contain "https://download.opensuse.org/tumbleweed/repo/oss/"

  # Scenario: Adding a new repository
  #   Given I start the "/usr/sbin/yast2 repositories" application
  #   Then the dialog heading should be "Configured Software Repositories"
  #
  #   When I click button "Add"
  #   Then the dialog heading should be "Add On Product"
  #
  #   When I click button "Next"
  #   Then the dialog heading should be "Repository URL"
  #
  #   When I enter "Tumbleweed OSS" into input field "Repository Name"
  #   And I enter "https://download.opensuse.org/tumbleweed/repo/oss/" into input field "URL"
  #   And I click button "Next"
  #   Then the dialog heading should be "Tumbleweed OSS License Agreement"
  #
  #   When I click button "Next"
  #   Then the dialog heading should be "Configured Software Repositories"
  #   Then I click button "OK"
  #   Then I wait for the application to finish
  #
  #   # verify that the tested repository was really added
  #   When I run `zypper lr -u `
  #   Then the output should contain "https://download.opensuse.org/tumbleweed/repo/oss/"
