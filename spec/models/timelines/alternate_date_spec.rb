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

require File.expand_path('../../../spec_helper', __FILE__)

describe Timelines::AlternateDate do
  describe '- Relations ' do
    describe '#project' do
      it 'can read the planning_element w/ the help of the belongs_to association' do
        planning_element = FactoryGirl.create(:timelines_planning_element)
        alternate_date   = FactoryGirl.create(:timelines_alternate_date,
                                          :planning_element_id => planning_element.id)

        alternate_date.reload

        alternate_date.planning_element.should == planning_element
      end

      it 'can read the scenario w/ the help of the belongs_to association' do
        scenario       = FactoryGirl.create(:timelines_scenario)
        alternate_date = FactoryGirl.create(:timelines_alternate_date,
                                        :scenario_id => scenario.id)

        alternate_date.reload

        alternate_date.scenario.should == scenario
      end
    end
  end

  describe '- Scopes ' do
    describe '.historic' do
      it 'contains only elements not belonging to a scenario' do
        planning_element = FactoryGirl.create(:timelines_planning_element)

        # created automatically when creating the planning element
        alternate_date1  = planning_element.alternate_dates.first

        scenario        = FactoryGirl.create(:timelines_scenario)
        alternate_date2 = FactoryGirl.create(:timelines_alternate_date,
                                         :scenario_id         => scenario.id,
                                         :planning_element_id => planning_element.id)

        Timelines::AlternateDate.historic.size.should == 1
        Timelines::AlternateDate.historic.should be_include(alternate_date1)
        Timelines::AlternateDate.historic.should_not be_include(alternate_date2)
      end
    end

    describe '.scenaric' do
      it 'contains only elements belonging to a scenario' do
        planning_element = FactoryGirl.create(:timelines_planning_element)

        # created automatically when creating the planning element
        alternate_date1  = planning_element.alternate_dates.first

        scenario        = FactoryGirl.create(:timelines_scenario)
        alternate_date2 = FactoryGirl.create(:timelines_alternate_date,
                                         :scenario_id => scenario.id)

        Timelines::AlternateDate.scenaric.size.should == 1
        Timelines::AlternateDate.scenaric.should_not be_include(alternate_date1)
        Timelines::AlternateDate.scenaric.should be_include(alternate_date2)
      end
    end
  end

  describe '- Validations ' do
    let(:attributes) {
      {:planning_element_id => 1,
       :start_date => Date.today,
       :end_date   => Date.today + 2.weeks}
    }

    before { FactoryGirl.create(:timelines_planning_element, :id => 1) }

    it { Timelines::AlternateDate.new.tap { |ad| ad.send(:assign_attributes, attributes, :without_protection => true) }.should be_valid }

    describe 'start_date' do
      it 'is invalid w/o a start_date' do
        attributes[:start_date] = nil
        alternate_date = Timelines::AlternateDate.new.tap { |ad| ad.send(:assign_attributes, attributes, :without_protection => true) }

        alternate_date.should_not be_valid

        alternate_date.errors[:start_date].should be_present
        alternate_date.errors[:start_date].should == ["can't be blank"]
      end
    end

    describe 'end_date' do
      it 'is invalid w/o a end_date' do
        attributes[:end_date] = nil
        alternate_date = Timelines::AlternateDate.new.tap { |ad| ad.send(:assign_attributes, attributes, :without_protection => true) }

        alternate_date.should_not be_valid

        alternate_date.errors[:end_date].should be_present
        alternate_date.errors[:end_date].should == ["can't be blank"]
      end

      it 'is invalid if start_date is after end_date' do
        attributes[:start_date] = Date.today
        attributes[:end_date]   = Date.today - 1.week
        alternate_date = Timelines::AlternateDate.new.tap { |ad| ad.send(:assign_attributes, attributes, :without_protection => true) }

        alternate_date.should_not be_valid

        alternate_date.errors[:end_date].should be_present
        alternate_date.errors[:end_date].should == ["must be greater than start date"]
      end

      it 'is invalid if planning_element is milestone and end_date is not on start_date' do
        planning_element_type         = FactoryGirl.build(:timelines_planning_element_type, :is_milestone => true)
        attributes[:start_date]       = Date.today
        attributes[:end_date]         = Date.today + 1.week
        attributes[:planning_element] = FactoryGirl.build(:timelines_planning_element, :planning_element_type => planning_element_type)
        alternate_date = Timelines::AlternateDate.new.tap { |ad| ad.send(:assign_attributes, attributes, :without_protection => true) }

        alternate_date.should_not be_valid

        alternate_date.errors[:end_date].should be_present
        alternate_date.errors[:end_date].should == ["is not on start date, although this is required for milestones"]
      end
    end

    describe 'planning_element' do
      it 'is invalid w/o a planning_element' do
        attributes[:planning_element_id] = nil
        alternate_date = Timelines::AlternateDate.new.tap { |ad| ad.send(:assign_attributes, attributes, :without_protection => true) }

        alternate_date.should_not be_valid

        alternate_date.errors[:planning_element].should be_present
        alternate_date.errors[:planning_element].should == ["can't be blank"]
      end
    end
  end

  describe ' - Instance Methods' do
    it_should_behave_like "a model with non-negative duration"
  end
end
