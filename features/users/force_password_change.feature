#encoding: utf-8

#-- copyright
# OpenProject is a project management system.
#
# Copyright (C) 2012-2013 the OpenProject Team
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License version 3.
#
# See doc/COPYRIGHT.rdoc for more details.
#++

Feature: Forced Password Change
  Background:
    Given there is a user named "bob"
    Given the user "bob" is forced to change his password

  Scenario: A user providing non valid credentials on forced password change
    And I try to log in with user "bob"
    When I fill out the change password form with a wrong old password
    Then there should be a flash error message
    And I should see "Invalid user or password"
    And there should be a "New password" field

  Scenario: Setting forced password change for a user forces him to change password on next login
    Given I am already logged in as "admin"
    And I go to the edit page for the user called "bob"
    And I check "Enforce password change on next login"
    And I press "Save"
    And I try to log in with user "bob"
    Then there should be a flash error message
    And there should be a "New password" field

  Scenario: A user is forced to change the password on the first login, but not on the second
    When I try to log in with user "bob"
    And I fill out the change password form
    Then there should be a flash notice message
    And I should see "Bob Bobbit"
    # Try again to check password change is not enforced on second login
    And I try to log in with user "bob"
    Then I should see "Bob Bobbit"
