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

require 'rails_generator/base'
require 'rails_generator/generators/components/controller/controller_generator'

class ChiliprojectPluginControllerGenerator < ControllerGenerator
  attr_reader :plugin_path, :plugin_name, :plugin_pretty_name

  def initialize(runtime_args, runtime_options = {})
    runtime_args = runtime_args.dup
    usage if runtime_args.empty?
    @plugin_name = "chiliproject_" + runtime_args.shift.underscore
    @plugin_pretty_name = plugin_name.titleize
    @plugin_path = "vendor/plugins/#{plugin_name}"
    super(runtime_args, runtime_options)
  end

  def destination_root
    Rails.root.join(plugin_path).to_s
  end

  def manifest
    record do |m|
      # Check for class naming collisions.
      m.class_collisions class_path, "#{class_name}Controller", "#{class_name}ControllerTest", "#{class_name}Helper"

      # Controller, helper, views, and test directories.
      m.directory File.join('app/controllers', class_path)
      m.directory File.join('app/helpers', class_path)
      m.directory File.join('app/views', class_path, file_name)
      m.directory File.join('test/functional', class_path)

      # Controller class, functional test, and helper class.
      m.template 'controller.rb.erb',
                  File.join('app/controllers',
                            class_path,
                            "#{file_name}_controller.rb")

      m.template 'functional_test.rb.erb',
                  File.join('test/functional',
                            class_path,
                            "#{file_name}_controller_test.rb")

      m.template 'helper.rb.erb',
                  File.join('app/helpers',
                            class_path,
                            "#{file_name}_helper.rb")

      # View template for each action.
      actions.each do |action|
        path = File.join('app/views', class_path, file_name, "#{action}.html.erb")
        m.template 'view.html.erb', path,
          :assigns => { :action => action, :path => path }
      end
    end
  end
end
