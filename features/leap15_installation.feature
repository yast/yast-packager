Feature: Test the openSUSE Leap 15.0 installation

  Scenario: Simple minimal installation

    Given I attach to a runnig YaST installation application
    Then the dialog heading should be "Language, Keyboard and License Agreement"
    And label "License Agreement" should be displayed
    And the combo box "Language" should have value "English (US)"
    And the combo box "Keyboard Layout" should have value "English (US)"

    When I click button "License Translations..."
    Then a popup should be displayed
    And widget "License Agreement" should be displayed
    And the combo box "Language" should have value "English (US)"

    When I click button "OK"
    Then the dialog heading should be "Language, Keyboard and License Agreement"

    When I click button "Next"
    # more time for the initialization
    Then the dialog heading should be "User Interface" in 30 seconds
    And the radio button "Desktop with KDE Plasma" should be selected
    And the radio button "Desktop with GNOME" should not be selected

    Then I select radio button "Server"
    When I click button "Next"
    Then the dialog heading should be "Suggested Partitioning"

    When I click button "Next"
    # the NTP synchronization might take some time...
    Then the dialog heading should be "Clock and Time Zone" in 30 seconds

    When I click button "Next"
    Then the dialog heading should be "Local User"
    And I enter "John Smith" into input field "User's Full Name"
    And I enter "jonny" into input field "Username"
    And I enter "password" into input field "Password"
    And I enter "password" into input field "Confirm Password"

    When I click button "Next"
    Then a popup should be displayed
    And a label including "The password is too simple" should be displayed
    And button "Yes" should be displayed
    And button "No" should be displayed

    When I click button "Yes"
    Then the dialog heading should be "Installation Settings"
    And widget "Install" should be displayed

    When I click button "Install"
    Then button "Install" should be displayed
    Then button "Back" should be displayed

    When I click button "Install"
    Then the dialog heading should be "Performing Installation"
