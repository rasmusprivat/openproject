#-- encoding: UTF-8
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

class TimelogController < ApplicationController
  menu_item :issues
  before_filter :find_project, :only => [:new, :create]
  before_filter :find_time_entry, :only => [:show, :edit, :update, :destroy]
  before_filter :authorize, :except => [:index]
  before_filter :find_optional_project, :only => [:index]
  accept_key_auth :index, :show, :create, :update, :destroy

  include SortHelper
  include TimelogHelper
  include CustomFieldsHelper

  def index
    sort_init 'spent_on', 'desc'
    sort_update 'spent_on' => 'spent_on',
                'user' => 'user_id',
                'activity' => 'activity_id',
                'project' => "#{Project.table_name}.name",
                'issue' => 'issue_id',
                'hours' => 'hours'

    cond = ARCondition.new
    if @issue
      cond << "#{Issue.table_name}.root_id = #{@issue.root_id} AND #{Issue.table_name}.lft >= #{@issue.lft} AND #{Issue.table_name}.rgt <= #{@issue.rgt}"
    elsif @project
      cond << @project.project_condition(Setting.display_subprojects_issues?)
    end

    retrieve_date_range
    cond << ['spent_on BETWEEN ? AND ?', @from, @to]

    respond_to do |format|
      format.html {
        # Paginate results
        @entry_count = TimeEntry.visible.count(:include => [:project, :issue], :conditions => cond.conditions)
        @entry_pages = Paginator.new self, @entry_count, per_page_option, params['page']
        @entries = TimeEntry.visible.find(:all,
                                  :include => [:project, :activity, :user, {:issue => :tracker}],
                                  :conditions => cond.conditions,
                                  :order => sort_clause,
                                  :limit  =>  @entry_pages.items_per_page,
                                  :offset =>  @entry_pages.current.offset)
        @total_hours = TimeEntry.visible.sum(:hours, :include => [:project, :issue], :conditions => cond.conditions).to_f

        render :layout => !request.xhr?
      }
      format.api  {
        @entry_count = TimeEntry.visible.count(:include => [:project, :issue], :conditions => cond.conditions)
        @entry_pages = Paginator.new self, @entry_count, per_page_option, params['page']
        @entries = TimeEntry.visible.find(:all,
                                  :include => [:project, :activity, :user, {:issue => :tracker}],
                                  :conditions => cond.conditions,
                                  :order => sort_clause,
                                  :limit  =>  @entry_pages.items_per_page,
                                  :offset =>  @entry_pages.current.offset)
      }
      format.atom {
        entries = TimeEntry.visible.find(:all,
                                 :include => [:project, :activity, :user, {:issue => :tracker}],
                                 :conditions => cond.conditions,
                                 :order => "#{TimeEntry.table_name}.created_on DESC",
                                 :limit => Setting.feeds_limit.to_i)
        render_feed(entries, :title => l(:label_spent_time))
      }
      format.csv {
        # Export all entries
        @entries = TimeEntry.visible.find(:all,
                                  :include => [:project, :activity, :user, {:issue => [:tracker, :assigned_to, :priority]}],
                                  :conditions => cond.conditions,
                                  :order => sort_clause)
        send_data(entries_to_csv(@entries), :type => 'text/csv; header=present', :filename => 'timelog.csv')
      }
    end
  end

  def show
    respond_to do |format|
      # TODO: Implement html response
      format.html { render :nothing => true, :status => 406 }
      format.api
    end
  end

  def new
    @time_entry ||= TimeEntry.new(:project => @project, :issue => @issue, :user => User.current, :spent_on => User.current.today)
    @time_entry.safe_attributes = params[:time_entry]

    call_hook(:controller_timelog_edit_before_save, { :params => params, :time_entry => @time_entry })
    render :action => 'edit'
  end

  def create
    @time_entry ||= TimeEntry.new(:project => @project, :issue => @issue, :user => User.current, :spent_on => User.current.today)
    @time_entry.safe_attributes = params[:time_entry]

    call_hook(:controller_timelog_edit_before_save, { :params => params, :time_entry => @time_entry })

    if @time_entry.save
      respond_to do |format|
        format.html {
          flash[:notice] = l(:notice_successful_update)
          redirect_back_or_default :action => 'index', :project_id => @time_entry.project
        }
        format.api  { render :action => 'show', :status => :created, :location => time_entry_url(@time_entry) }
      end
    else
      respond_to do |format|
        format.html { render :action => 'edit' }
        format.api  { render_validation_errors(@time_entry) }
      end
    end
  end

  def edit
    @time_entry.safe_attributes = params[:time_entry]

    call_hook(:controller_timelog_edit_before_save, { :params => params, :time_entry => @time_entry })
  end

  def update
    @time_entry.safe_attributes = params[:time_entry]

    call_hook(:controller_timelog_edit_before_save, { :params => params, :time_entry => @time_entry })

    if @time_entry.save
      respond_to do |format|
        format.html {
          flash[:notice] = l(:notice_successful_update)
          redirect_back_or_default :action => 'index', :project_id => @time_entry.project
        }
        format.api  { head :ok }
      end
    else
      respond_to do |format|
        format.html { render :action => 'edit' }
        format.api  { render_validation_errors(@time_entry) }
      end
    end
  end

  def destroy
    if @time_entry.destroy && @time_entry.destroyed?
      respond_to do |format|
        format.html {
          flash[:notice] = l(:notice_successful_delete)
          redirect_to :back
        }
        format.api  { head :ok }
      end
    else
      respond_to do |format|
        format.html {
          flash[:error] = l(:notice_unable_delete_time_entry)
          redirect_to :back
        }
        format.api  { render_validation_errors(@time_entry) }
      end
    end
  rescue ::ActionController::RedirectBackError
    redirect_to :action => 'index', :project_id => @time_entry.project
  end

private
  def find_time_entry
    @time_entry = TimeEntry.find(params[:id])
    unless @time_entry.editable_by?(User.current)
      render_403
      return false
    end
    @project = @time_entry.project
  rescue ActiveRecord::RecordNotFound
    render_404
  end

  def find_project
    if (issue_id = (params[:issue_id] || params[:time_entry] && params[:time_entry][:issue_id])).present?
      @issue = Issue.find(issue_id)
      @project = @issue.project
    elsif (project_id = (params[:project_id] || params[:time_entry] && params[:time_entry][:project_id])).present?
      @project = Project.find(project_id)
    else
      render_404
      return false
    end
  rescue ActiveRecord::RecordNotFound
    render_404
  end

  def find_optional_project
    if !params[:issue_id].blank?
      @issue = Issue.find(params[:issue_id])
      @project = @issue.project
    elsif !params[:project_id].blank?
      @project = Project.find(params[:project_id])
    end
    deny_access unless User.current.allowed_to?(:view_time_entries, @project, :global => true)
  end

  # Retrieves the date range based on predefined ranges or specific from/to param dates
  def retrieve_date_range
    @free_period = false
    @from, @to = nil, nil

    if params[:period_type] == '1' || (params[:period_type].nil? && !params[:period].nil?)
      case params[:period].to_s
      when 'today'
        @from = @to = Date.today
      when 'yesterday'
        @from = @to = Date.today - 1
      when 'current_week'
        @from = Date.today - (Date.today.cwday - 1)%7
        @to = @from + 6
      when 'last_week'
        @from = Date.today - 7 - (Date.today.cwday - 1)%7
        @to = @from + 6
      when '7_days'
        @from = Date.today - 7
        @to = Date.today
      when 'current_month'
        @from = Date.civil(Date.today.year, Date.today.month, 1)
        @to = (@from >> 1) - 1
      when 'last_month'
        @from = Date.civil(Date.today.year, Date.today.month, 1) << 1
        @to = (@from >> 1) - 1
      when '30_days'
        @from = Date.today - 30
        @to = Date.today
      when 'current_year'
        @from = Date.civil(Date.today.year, 1, 1)
        @to = Date.civil(Date.today.year, 12, 31)
      end
    elsif params[:period_type] == '2' || (params[:period_type].nil? && (!params[:from].nil? || !params[:to].nil?))
      begin; @from = params[:from].to_s.to_date unless params[:from].blank?; rescue; end
      begin; @to = params[:to].to_s.to_date unless params[:to].blank?; rescue; end
      @free_period = true
    else
      # default
    end

    @from, @to = @to, @from if @from && @to && @from > @to
    @from ||= (TimeEntry.earliest_date_for_project(@project) || Date.today)
    @to   ||= (TimeEntry.latest_date_for_project(@project) || Date.today)
  end

  def default_breadcrumb
    I18n.t(:label_spent_time)
  end
end
