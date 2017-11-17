
Feature: To install the 3rd party packages I must be able to add a new package
  repository to the package management.

  Background:

    # make sure the tested repository does not already exist
    When I run `zypper repos --uri`
    Then the output should not contain "https://download.opensuse.org/tumbleweed/repo/oss/"


  @read-only @network
  Scenario: Aborting the repository manager keeps the old settings

    Given I start the "/usr/sbin/yast2 repositories" application
    Then the dialog heading should be "Configured Software Repositories"

    When I click button "Add"
    Then the dialog heading should be "Add On Product"

    When I click button "Next"
    Then the dialog heading should be "Repository URL"

    When I enter "Tumbleweed OSS" into input field "Repository Name"
    And I enter "https://download.opensuse.org/tumbleweed/repo/oss/" into input field "URL"
    And I click button "Next"
    Then the dialog heading should be "Tumbleweed OSS License Agreement" in 60 seconds

    When I click button "Next"
    Then the dialog heading should be "Configured Software Repositories"

    When I click button "Cancel"
    Then a popup should be displayed
    And the label including "Abort the repository configuration?" should be displayed

    Then I click button "Yes"
    And I wait for the application to finish

    # verify that the tested repository was NOT added
    When I run `zypper repos --uri`
    Then the output should not contain "https://download.opensuse.org/tumbleweed/repo/oss/"

  @network
  Scenario: The remote repository is added to the system

    Given I start the "/usr/sbin/yast2 repositories" application
    Then the dialog heading should be "Configured Software Repositories"

    When I click button "Add"
    Then the dialog heading should be "Add On Product"

    When I click button "Next"
    Then the dialog heading should be "Repository URL"

    When I enter "Tumbleweed OSS" into input field "Repository Name"
    And I enter "https://download.opensuse.org/tumbleweed/repo/oss/" into input field "URL"
    And I click button "Next"
    Then the dialog heading should be "Tumbleweed OSS License Agreement" in 60 seconds

    When I click button "Next"
    Then the dialog heading should be "Configured Software Repositories"

    Then I click button "OK"
    And I wait for the application to finish for up to 60 seconds

    # verify that the tested repository was added
    When I run `zypper repos --uri`
    Then the output should contain "https://download.opensuse.org/tumbleweed/repo/oss/"
