Feature: Test a plain libyui application

  Scenario: Test the `ManyWidgets` example app from libyui
    
    Given I start the ManyWidgets libyui example application

    # test the initial state
    Then label "Label" should be displayed
    And check box "Check0" should not be checked
    And check box "Check1" should be checked
    And widget "Event Loop" should be displayed

    # click push button
    Then I click button "Enabled"
    # enter values
    Then I enter "testing input" into input field "Public:"
    And I enter "my secret!" into input field "Secret:"
    # open a popup
    When I click button "Popup"
    Then label "Let it BEEP!" should be displayed
    And push button "Beep" should be displayed
    # close the popup
    Then I click button "Quit"

    # exit the application
    Then I click button "Quit"
    And I wait for the application to finish
