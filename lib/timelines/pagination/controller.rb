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

# Extending this module provides some convenience methods for easier setup of pagination inside a controller.
# It assumes there is just one pagination method to set up per model.
#
# To set up basic functions:
#   timelines_paginate_model Project
#
# This sets up the action #paginate_projects inside the controller.
#
# To change this action:
#
#   timelines_action_for Project, :my_own_action
#
# or use a block:
#
#   timelines_action_for Project do
#     do_something
#   end
#
# To set up multiple models at once:
# timelines_paginate_models Project, User
#
# To change the call the model uses for pagination (signature as in Timelines::Pagination::Model#paginate_scope!):
#   timelines_pagination_for Project, :my_own_pagination_method
#   timelines_pagination_for Project do |scope, opts|
#     do_something
#   end
#
# To change the scope the model uses to search (signature as in Timelines::Pagination::Model#search_scope):
#   timelines_search_for Project, :my_own_pagination_method
#   timelines_search_for Project do |query|
#     do_something
#   end
#
# Note that this needs to return an actual scope or its corresponding hash.
#
module Timelines::Pagination::Controller
  class Paginator
    attr_accessor :model, :action, :pagination, :search, :controller, :last_action, :block, :response

    def initialize(controller, model)
      self.controller = controller
      self.model = model
    end

    def self.resolve_model(model)
      (model.respond_to?(:constantize) ? model.constantize : model)
    end

    def default_action
      :"paginate_#{self.class.resolve_model(model).name.gsub('::', '_').underscore.downcase.pluralize}"
    end

    def default_pagination
      :'paginate_scope!'
    end

    def default_search
      :search_scope
    end

    def last_action
      @last_action ||= action
    end

    def action
      @action ||= default_action
    end

    def action=(action)
      @action = action
      refresh_action!
      return @action
    end

    def search
      @search ||= default_search
    end

    def pagination
      @pagination ||= default_pagination
    end

    def block
      @block ||= default_block
    end

    def response
      @response ||= default_response_block
    end

    def changed?
      last_action != action
    end

    def refresh_action!
      undef_action!
      define_action!
    end

    def undef_action!
      controller.timelines_pagination = controller.timelines_pagination.delete(last_action)

      # remove old
      controller.send(:remove_method, last_action) if controller.respond_to? :last_action
    end

    def define_action!(block = default_block)
      controller.timelines_pagination[action] = self
      raise NameError, "method '#{action}' already defined in #{controller}" if controller.respond_to? action
      controller.send(:define_method, action, block)
    end

    def default_block
      Proc.new {
        # TODO: less evilness
        paginator = self.class.timelines_pagination[__method__]
        size = params[:page_limit].to_i || 10
        page = params[:page]

        if page
          page = page.to_i

          methods = {}
          [:pagination, :search].each do |meth|
            methods[meth] = if paginator.send(meth).respond_to?(:call)
                paginator.send(meth)
              else
                paginator.model.method(paginator.send(meth))
              end
          end
          @paginated_items = methods[:pagination].call(methods[:search].call(params[:q]),
                               { :page => page, :page_limit => size }
                             )

          @more = @paginated_items.total_pages > page
          @total = @paginated_items.total_entries

          instance_eval(&(paginator.response))
        end
      }
    end

    def default_response_block
      Proc.new {
        respond_to do |format|
          format.json { render :json => { :results =>
            { :items => @paginated_items.collect {|item| { :id => item.id, :name => item.name } },
              :total => @total ? @total : @paginated_items.size,
              :more  => @more ? @more : 0 }
          } }
        end
      }
    end

  end

  def self.included(base)
    base.extend self
  end

  def self.extended(base)
    base.instance_eval do
      unloadable

      def timelines_paginate_models(*args)
        args.each do |arg|
          timelines_paginate_model(arg)
        end
      end

      def timelines_paginate_model(model)
        timelines_pagination_class.resolve_model(model)
        timelines_pagination[model] = (timelines_pagination_class.new(self, model))
        timelines_pagination[model].refresh_action!
      end

      def timelines_pagination_class
        @timelines_pagination_class ||= Timelines::Pagination::Controller::Paginator
      end

      def timelines_pagination_class=(struct)
        @timelines_pagination_class = struct
      end

      def timelines_pagination=(calls)
        @timelines_pagination = calls
      end

      def timelines_pagination
        @timelines_pagination ||= {}
      end

      # Has to return a method that takes a query as an argument
      # See Timelines::pagination::Model#paginate_scope!
      def timelines_pagination_for(model, call)
        resolve_paginator_for(model).pagination = (call.respond_to?(:call) ? call : call.to_s.to_sym)
      end

      def timelines_search_for(model, call)
        resolve_paginator_for(model).search = (call.respond_to?(:call) ? call : call.to_s.to_sym)
      end

      def timelines_action_for(model, call)
        resolve_paginator_for(model).action = (call.respond_to?(:call) ? call : call.to_s.to_sym)
      end

      def timelines_response_for(model, call)
        resolve_paginator_for(model).response = (call.respond_to?(:call) ? call : call.to_s.to_sym)
      end

      private

      def resolve_paginator_for(model)
        model = timelines_pagination_class.resolve_model(model)
        inst = timelines_pagination.find { |_,pag| pag.model == model }[1]

        if inst.nil?
          raise ArgumentError, "Model #{model} is not being paginated. Call #timelines_paginate_model(s) first."
        else
          return inst
        end
      end
    end
  end

end
