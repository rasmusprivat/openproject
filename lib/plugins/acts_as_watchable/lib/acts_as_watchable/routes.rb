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

module OpenProject
  module Acts
    module Watchable
      module Routes
        mattr_accessor :models

        def self.matches?(request)
          params = request.path_parameters

          watched?(params[:object_type]) &&
          /\d+/.match(params[:object_id])
        end

        def self.add_watched(watched)
          self.models ||= []

          self.models << watched.to_s unless self.models.include?(watched.to_s)

          @watchregexp = Regexp.new(self.models.join("|"))
        end

        private

        def self.watched?(object)
          @watchregexp.present? && @watchregexp.match(object).present?
        end
      end
    end
  end
end
