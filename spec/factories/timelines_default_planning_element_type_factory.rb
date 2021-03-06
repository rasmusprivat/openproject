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

FactoryGirl.define do
  factory(:timelines_default_planning_element_type, :class => Timelines::DefaultPlanningElementType) do
    project_type          { |e| e.association(:timelines_project_type) }
    planning_element_type { |e| e.association(:timelines_planning_element_type) }
  end
end
