#-- encoding: UTF-8
#-- copyright
# ChiliProject is a project management system.
#
# Copyright (C) 2010-2011 the ChiliProject Team
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# See doc/COPYRIGHT.rdoc for more details.
#++
require File.expand_path('../../test_helper', __FILE__)

class DefaultDataTest < ActiveSupport::TestCase
  include Redmine::I18n

  def setup
    super
    delete_loaded_data!
    refute Redmine::DefaultData::Loader.data_already_loaded?
  end

  def test_data_already_loaded
    Redmine::DefaultData::Loader.load
    assert Redmine::DefaultData::Loader.data_already_loaded?

    delete_loaded_data!
    refute Redmine::DefaultData::Loader.data_already_loaded?
  end

  def test_no_data
    Redmine::DefaultData::Loader.load
    refute Redmine::DefaultData::Loader.no_data?

    delete_loaded_data!
    assert Redmine::DefaultData::Loader.no_data?
  end

  def test_load
    valid_languages.each do |lang|
      begin
        delete_loaded_data!
        assert Redmine::DefaultData::Loader::load(lang)
        klasses.each do |klass|
          assert klass.any?
        end
      rescue ActiveRecord::RecordInvalid => e
        assert false, ":#{lang} default data is invalid (#{e.message})."
      end
    end
  end

private

  def delete_loaded_data!
    klasses.each(&:delete_all)
  end

  def klasses
    [
      User, Role, Tracker, IssueStatus,
      Enumeration, Workflow, DocumentCategory,
      IssuePriority, TimeEntryActivity
    ]
  end
end
