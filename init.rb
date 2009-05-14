require 'lib/statistics'
ActiveRecord::Base.send(:include, Statistics)
