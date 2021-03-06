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

class Timelines::PlanningElement < ActiveRecord::Base
  unloadable

  self.table_name = 'timelines_planning_elements'

  acts_as_tree

  include Timelines::TimestampsCompatibility
  include Timelines::NestedAttributesForApi
  include ActiveModel::ForbiddenAttributesProtection

  belongs_to :project,     :class_name => "Project"
  belongs_to :responsible, :class_name => "User",
                           :foreign_key => "responsible_id"

  belongs_to :planning_element_type,   :class_name  => "Timelines::PlanningElementType",
                                       :foreign_key => 'planning_element_type_id'
  belongs_to :planning_element_status, :class_name  => "Timelines::PlanningElementStatus",
                                       :foreign_key => 'planning_element_status_id'

  has_many :alternate_dates, :class_name  => "Timelines::AlternateDate",
                             :foreign_key => 'planning_element_id',
                             :autosave    => true,
                             :dependent   => :delete_all

  accepts_nested_attributes_for_apis_for :parent,
                                         :planning_element_status,
                                         :planning_element_type,
                                         :project

  acts_as_watchable

  acts_as_journalized :activity_type => 'timelines_planning_elements',
                      :activity_permission => :view_planning_elements,
                      :event_url   => Proc.new { |j| {:controller => 'timelines_planning_elements',
                                                      :action     => 'show',
                                                      :id         => j.journaled,
                                                      :project_id => j.project,
                                                      :anchor     => ("note-#{j.anchor}" unless j.initial?)} }

  # This SQL only works when there are no two updates in the same
  # millisecond. As soon as updates happen in rapid succession, multiple
  # instances of one planning element are returned.

  SQL_FOR_AT = {
    :select => "#{Timelines::PlanningElement.quoted_table_name}.id,
                #{Timelines::PlanningElement.quoted_table_name}.name,
                #{Timelines::PlanningElement.quoted_table_name}.description,
                #{Timelines::PlanningElement.quoted_table_name}.planning_element_status_comment,
                #{Timelines::AlternateDate.quoted_table_name  }.start_date,
                #{Timelines::AlternateDate.quoted_table_name  }.end_date,
                #{Timelines::PlanningElement.quoted_table_name}.parent_id,
                #{Timelines::PlanningElement.quoted_table_name}.project_id,
                #{Timelines::PlanningElement.quoted_table_name}.responsible_id,
                #{Timelines::PlanningElement.quoted_table_name}.planning_element_type_id,
                #{Timelines::PlanningElement.quoted_table_name}.planning_element_status_id,
                #{Timelines::PlanningElement.quoted_table_name}.created_at,
                #{Timelines::PlanningElement.quoted_table_name}.deleted_at,
                #{Timelines::AlternateDate.quoted_table_name  }.updated_at",
    :joins => "LEFT JOIN (
                  SELECT
                    #{Timelines::AlternateDate.quoted_table_name}.planning_element_id,
                    MAX(#{Timelines::AlternateDate.quoted_table_name}.updated_at) AS updated_at
                  FROM #{Timelines::AlternateDate.quoted_table_name}
                  WHERE
                    #{Timelines::AlternateDate.quoted_table_name}.created_at <= ?
                  GROUP BY
                    #{Timelines::AlternateDate.quoted_table_name}.planning_element_id
                )  AS timelines_alternate_dates_sub
                  ON #{Timelines::PlanningElement.quoted_table_name}.id = timelines_alternate_dates_sub.planning_element_id
              INNER JOIN
                #{Timelines::AlternateDate.quoted_table_name}
                  ON #{Timelines::AlternateDate.quoted_table_name}.planning_element_id = timelines_alternate_dates_sub.planning_element_id
                    AND #{Timelines::AlternateDate.quoted_table_name}.updated_at = timelines_alternate_dates_sub.updated_at"

  }

  scope :without_deleted, :conditions => "#{Timelines::PlanningElement.quoted_table_name}.deleted_at IS NULL"
  scope :deleted, :conditions => "#{Timelines::PlanningElement.quoted_table_name}.deleted_at IS NOT NULL"
  scope :visible, lambda {|*args| { :include => :project,
                                          :conditions => Timelines::PlanningElement.visible_condition(args.first || User.current) } }

  alias_method :destroy!, :destroy

  scope :at_time, lambda { |time|
    {:select     => SQL_FOR_AT[:select],
     :conditions => ["(#{Timelines::PlanningElement.quoted_table_name}.deleted_at IS NULL
                        OR #{Timelines::PlanningElement.quoted_table_name}.deleted_at >= ?)", time],
     :joins      => sanitize_sql([SQL_FOR_AT[:joins], time]),
     :readonly   => true
    }
  }

  scope :for_projects, lambda { |projects|
    {:conditions => {:project_id => projects}}
  }

  def self.visible_condition(user, options={})
    Project.allowed_to_condition(user, :view_planning_elements, options)
  end

  # Used for journal entry / activities list
  def activity_type
    'timelines_planning_elements'
  end

  # Used for activities list
  def title
    title = ''
    title << name
    title << ' ('
    title << planning_element_type.name << ' ' if planning_element_type
    title << '*'
    title << id.to_s
    title << ')'
  end

  register_on_journal_formatter :plaintext,         :name, :description,
                                                    :planning_element_status_comment
  register_on_journal_formatter :named_association, :parent_id, :project_id,
                                                    :planning_element_type_id,
                                                    :planning_element_status_id,
                                                    :responsible_id
  register_on_journal_formatter :datetime,          :start_date, :end_date, :deleted_at

  register_on_journal_formatter :scenario_date,     /^scenario_(\d+)_(start|end)_date$/

  # Overriding Journal Class to provide extended information in activity view
  journal_class.class_eval do
    def event_title
      if initial?
        I18n.t("timelines.planning_element_creation", :title => journalized.title)
      else
        I18n.t("timelines.planning_element_update", :title => journalized.title)
      end
    end
  end

  def append_scenario_dates_to_journal
    changes = {}
    alternate_dates.each do |d|
      if d.scenario.present? && (!(alternate_date_changes = d.changes).empty? || d.marked_for_destruction?)
        ["start_date", "end_date"].each do |field|
          old_value = if (scenario_changes = alternate_date_changes["scenario_id"])
            scenario_changes.first.nil? ? nil : d.send(field)
          else
            alternate_date_changes[field].nil? ? d.send(field) : alternate_date_changes[field].first
          end
          new_value = d.marked_for_destruction? ? nil : d.send(field)
          changes.merge!({ "scenario_#{d.scenario.id}_#{field}" => [old_value, new_value] }) unless new_value == old_value
        end
      end
    end
    journal_changes.append_changes!(changes)
  end

  before_save :append_scenario_dates_to_journal

  after_save :update_parent_attributes
  after_save :create_alternate_date

  validates_presence_of :name, :start_date, :end_date, :project

  validates_length_of :name, :maximum => 255, :unless => lambda { |e| e.name.blank? }

  def duration
    if start_date >= end_date
      1
    else
      end_date - start_date + 1
    end
  end

  def is_milestone?
    planning_element_type && planning_element_type.is_milestone?
  end

  validate do
    if self.end_date and self.start_date and self.end_date < self.start_date
      errors.add :end_date, :greater_than_start_date
    end

    if self.is_milestone?
      if self.end_date and self.start_date and self.start_date != self.end_date
        errors.add :end_date, :not_start_date
      end
    end

    if self.parent
      errors.add :parent, :cannot_be_milestone if parent.is_milestone?
      errors.add :parent, :cannot_be_in_another_project if parent.project != project
      errors.add :parent, :cannot_be_in_recycle_bin if parent.deleted?
      errors.add :parent, :circular_dependency if ancestors.include?(self)
    end

  end

  def leaf?
    self.children.count == 0
  end

  def all_scenarios
    project.timelines_scenarios.sort_by(&:id).map do |scenario|
      alternate_date = alternate_dates.to_a.find { |a| a.scenario_id.to_s == scenario.id.to_s }
      alternate_date ||= alternate_dates.build.tap { |ad| ad.scenario_id = scenario.id }
      Timelines::PlanningElementScenario.new(alternate_date)
    end
  end

  def scenarios
    alternate_dates.scenaric.sort_by(&:scenario_id).map do |alternate_date|
      Timelines::PlanningElementScenario.new(alternate_date)
    end
  end

  # Expecting pe_scenarios to be an Array of Hashes or a Hash of Hashes with
  # arbitrary keys following the following schema:
  #
  #   {
  #     'id' => 1,
  #     'start_date => '2012-01-01',
  #     'end_date' => '2012-01-03'
  #   }
  #
  # The id attribute is required. If both date fields are empty or missing, the
  # alternate date will be deleted. The alternate date will also be deleted,
  # when the "_destroy" key is present and set to "1".
  #
  # Other attributes will be silently ignored.
  #
  def scenarios=(pe_scenarios)
    pe_scenarios = pe_scenarios.values if pe_scenarios.is_a? Hash

    pe_scenarios.each do |pe_scenario|
      alternate_date = alternate_dates.to_a.find { |date| date.scenario_id.to_s == pe_scenario['id'].to_s }
      unless alternate_date
        if self.new_record?
          alternate_date = Timelines::AlternateDate.new.tap { |ad| ad.scenario_id = pe_scenario['id'] }
          alternate_date.planning_element = self
          alternate_dates << alternate_date
        else
          alternate_date = alternate_dates.build.tap { |ad| ad.scenario_id = pe_scenario['id'] }
        end
      end

      if (pe_scenario['start_date'].blank? and pe_scenario['end_date'].blank?) or
          pe_scenario['_destroy'] == '1'
        alternate_date.mark_for_destruction
      else
        alternate_date.attributes = {'start_date' => pe_scenario['start_date'],
                                     'end_date'   => pe_scenario['end_date']}
      end
    end
  end

  def note
    @journal_notes
  end

  def note=(text)
    @journal_notes = text
  end


  def destroy
    unless new_record?
      self.children.each{|child| child.destroy}

      self.deleted_at = Time.now
      self.save!
    end
    freeze
  end

  def has_many_dependent_for_children
    # Overwrites :dependent => :destroy - before_destroy callback
    # since we need to call the destroy! method instead of the destroy
    # method which just moves the element to the recycle bin
    children.each {|child| child.destroy!}
  end

  def restore!
    unless parent && parent.deleted?
      self.deleted_at = nil
      self.save
    else
      raise "You cannot restore an element whose parent is deleted. Restore the parent first!"
    end
  end

  def deleted?
    !!read_attribute(:deleted_at)
  end


  protected

  def update_parent_attributes
    if parent.present?
      parent.reload

      unless parent.children.without_deleted.empty?
        parent.start_date = parent.children.without_deleted.minimum(:start_date)
        parent.end_date   = parent.children.without_deleted.maximum(:end_date)

        if parent.changes.present?
          parent.note = I18n.t('timelines.planning_element_updated_automatically_by_child_changes', :child => "*#{id}")

          # Ancestors will be updated by parent's after_save hook.
          parent.save(:validate => false)
        end
      end
    end
  end

  def create_alternate_date
    if start_date_changed? or end_date_changed?
      alternate_dates.create(:start_date => start_date, :end_date => end_date)
    end
  end
end
