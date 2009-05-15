require File.join(File.dirname(__FILE__), 'lib', 'statistics')
ActiveRecord::Base.send(:include, Statistics)
