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

class Timelines::TimelinesReportingsController < ApplicationController
  unloadable
  helper :timelines

  before_filter :find_project_by_project_id
  before_filter :authorize

  accept_key_auth :index, :show

  menu_item :timelines_reportings

  def available_projects
    available_projects = @project.timelines_reporting_to_project_candidates
    respond_to do |format|
      format.html { render_404 }
      format.api {
        @elements = Project.project_level_list(Project.visible)
        @disabled = Project.visible - available_projects
      }
    end
  end

  def index

    condition_params = [];
    temp_condition = ""
    condition = ""

    if (params[:project_types].present?)
      project_types = params[:project_types].split(/,/).map(&:to_i)
      temp_condition += "#{Project.quoted_table_name}.timelines_project_type_id IN (?)"
      condition_params << project_types
      if (project_types.include?(-1))
        temp_condition += " OR #{Project.quoted_table_name}.timelines_project_type_id IS NULL"
        temp_condition = "(#{temp_condition})"
      end
    end

    condition += temp_condition
    temp_condition = ""

    if (params[:project_statuses].present?)
      condition += " AND " unless condition.empty?

      project_statuses = params[:project_statuses].split(/,/).map(&:to_i)
      temp_condition += "#{Timelines::Reporting.quoted_table_name}.reported_project_status_id IN (?)"
      condition_params << project_statuses
      if (project_statuses.include?(-1))
        temp_condition += " OR #{Timelines::Reporting.quoted_table_name}.reported_project_status_id IS NULL"
        temp_condition = "(#{temp_condition})"
      end
    end

    condition += temp_condition
    temp_condition = ""

    if (params[:project_responsibles].present?)
      condition += " AND " unless condition.empty?

      project_responsibles = params[:project_responsibles].split(/,/).map(&:to_i)
      temp_condition += "#{Project.quoted_table_name}.timelines_responsible_id IN (?)"
      condition_params << project_responsibles
      if (project_responsibles.include?(-1))
        temp_condition += " OR #{Project.quoted_table_name}.timelines_responsible_id  IS NULL"
        temp_condition = "(#{temp_condition})"
      end
    end

    condition += temp_condition
    temp_condition = ""

    if (params[:project_parents].present?)
      condition += " AND " unless condition.empty?

      project_parents = params[:project_parents].split(/,/).map(&:to_i)
      nested_set_selection = Project.find(project_parents).map { |p| p.lft..p.rgt }.inject([]) { |r, e| e.each { |i| r << i }; r }

      temp_condition += "#{Project.quoted_table_name}.lft IN (?)"
      condition_params << nested_set_selection
    end

    condition += temp_condition
    temp_condition = ""

    if (params[:grouping_one].present? && condition.present?)
      condition += " OR "

      grouping = params[:grouping_one].split(/,/).map(&:to_i)
      temp_condition += "#{Project.quoted_table_name}.id IN (?)"
      condition_params << grouping
    end

    condition += temp_condition
    conditions = [condition] + condition_params unless condition.empty?

    case params[:only]
    when "via_source"
      @reportings = @project.timelines_reportings_via_source.find(:all,
          :include => :project,
          :conditions => conditions
        )
    when "via_target"
      @reportings = @project.timelines_reportings_via_target.find(:all,
          :include => :project,
          :conditions => conditions
        )
    else
      @reportings = @project.timelines_reportings.all
    end

    # get all reportings for which projects have ancestors.
    nested_sets_for_parents = (@reportings.inject([]) { |r, e| r << e.reporting_to_project; r << e.project }).uniq.map { |p| [p.lft, p.rgt] }

    condition_params = [];
    temp_condition = ""
    condition = ""

    nested_sets_for_parents.each do |set|
      condition += " OR " unless condition.empty?
      condition += "#{Project.quoted_table_name}.lft < ? AND #{Project.quoted_table_name}.rgt > ?"
      condition_params << set[0]
      condition_params << set[1]
    end

    conditions = [condition] + condition_params unless condition.empty?

    case params[:only]
    when "via_source"
      @ancestor_reportings = @project.timelines_reportings_via_source.find(:all,
          :include => :project,
          :conditions => conditions
        )
    when "via_target"
      @ancestor_reportings = @project.timelines_reportings_via_target.find(:all,
          :include => :project,
          :conditions => conditions
        )
    else
      @ancestor_reportings = @project.timelines_reportings.all
    end

    @reportings = (@reportings + @ancestor_reportings).uniq

    respond_to do |format|
      format.html do
        @reportings = @project.timelines_reportings_via_source.all.select(&:visible?)
      end
      format.api do
        @reportings.select(&:visible?)
      end
    end
  end

  def show
    @reporting = @project.timelines_reportings_via_source.find(params[:id])
    check_visibility

    respond_to do |format|
      format.html
      format.api
    end
  end

  def new
    @reporting_to_project_candidates = @project.timelines_reporting_to_project_candidates
    if @reporting_to_project_candidates.blank?
      flash[:warning] = l('timelines.no_projects_for_reporting_available')
      redirect_to timelines_project_reportings_path(@project)
    else
      @reporting = Timelines::Reporting.new

      respond_to do |format|
        format.html
      end
    end
  end

  def create
    @reporting = @project.timelines_reportings_via_source.build
    @reporting.reporting_to_project_id = params['reporting']['reporting_to_project_id']
    check_visibility

    if @reporting.save
      flash[:notice] = l(:notice_successful_create)
      redirect_to timelines_project_reportings_path
    else
      flash.now[:error] = l('timelines.reporting_could_not_be_saved')
      render :action => 'new'
    end
  end

  def edit
    @reporting = @project.timelines_reportings_via_source.find(params[:id])
    check_visibility

    respond_to do |format|
      format.html
    end
  end

  def update
    @reporting = @project.timelines_reportings_via_source.find(params[:id])
    check_visibility

    if @reporting.update_attributes(params[:reporting])
      flash[:notice] = l(:notice_successful_update)
      redirect_to timelines_project_reportings_path
    else
      flash.now[:error] = l('timelines.reporting_could_not_be_saved')
      render :action => :edit
    end
  end

  def confirm_destroy
    @reporting = @project.timelines_reportings_via_source.find(params[:id])
    check_visibility

    respond_to do |format|
      format.html
    end
  end

  def destroy
    @reporting = @project.timelines_reportings_via_source.find(params[:id])
    check_visibility
    @reporting.destroy

    flash[:notice] = l(:notice_successful_delete)
    redirect_to timelines_project_reportings_path
  end

  protected

  def check_visibility
    raise ActiveRecord::RecordNotFound unless @reporting.visible?
  end

  def default_breadcrumb
    l('timelines.project_menu.reportings')
  end
end
