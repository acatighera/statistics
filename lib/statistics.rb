module Statistics
  class << self
    def included(base)
      base.extend(HasStats)
    end

    def default_filters(filters)
      ActiveRecord::Base.instance_eval { @filter_all_on = filters }
    end

    def supported_calculations
      [:average, :count, :maximum, :minimum, :sum]
    end

    def supported_time_ranges
      [ :range_today, :range_week, :range_month, :range_year ]
    end
  end

  # This extension provides the ability to define statistics for reporting purposes
  module HasStats

    # OPTIONS:
    #
    #* +average+, +count+, +sum+, +maximum+, +minimum+ - Only one of these keys is passed, which
    #   one depends on the type of operation. The value is an array of named scopes to scope the
    #   operation by (+:all+ should be used if no scopes are to be applied)
    #* +column_name+ - The SQL column to perform the operation on (default: +id+)
    #* +filter_on+ - A hash with keys that represent filters. The with values in the has are rules
    #   on how to generate the query for the correspond filter.
    #* +cached_for+ - A duration for how long to cache this specific statistic
    #
    #   Additional options can also be passed in that would normally be passed to an ActiveRecord
    #   +calculate+ call, like +conditions+, +joins+, etc
    #
    # EXAMPLE:
    #
    #  class MockModel < ActiveRecord::Base
    #
    #    named_scope :my_scope, :conditions => 'value > 5'
    #
    #    define_statistic "Basic Count", :count => :all
    #    define_statistic "Basic Sum", :sum => :all, :column_name => 'amount'
    #    define_statistic "Chained Scope Count", :count => [:all, :my_scope]
    #    define_statistic "Default Filter", :count => :all
    #    define_statistic "Custom Filter", :count => :all, :filter_on => { :channel => 'channel = ?', :start_date => 'DATE(created_at) > ?' }
    #    define_statistic "Cached", :count => :all, :filter_on => { :channel => 'channel = ?', :blah => 'blah = ?' }, :cache_for => 1.second
    #  end
    def define_statistic(name, options)
      method_name = name.to_s.gsub(" ", "").underscore + "_stat"

      @statistics ||= {}
      @filter_all_on ||= ActiveRecord::Base.instance_eval { @filter_all_on }
      @statistics[name] = method_name

      options = { :column_name => :id }.merge(options)

      calculation = options.keys.find {|opt| Statistics::supported_calculations.include?(opt)}
      calculation ||= :count

      # We must use the metaclass here to metaprogrammatically define a class method
      (class<<self; self; end).instance_eval do
        define_method(method_name) do |filters|
          # check the cache before running a query for the stat
          # TODO: Better TIME RANGE support when caching requests!
          cached_val = Rails.cache.read("#{self.name}#{method_name}#{filters}") if options[:cache_for]
          return cached_val unless cached_val.nil?

          scoped_options = Marshal.load(Marshal.dump(options))

          filters.each do |key, value|
            unless value.nil?
              if Statistics::supported_time_ranges.include? key
                # In key is time_range type and in key is FIELD
                range = nil
                case key
                  when :range_today then
                    range = Time.now.all_day
                  when :range_week
                    range = Time.now.all_week
                  when :range_month then
                    range = Time.now.all_month
                  when :range_year then
                    range = Time.now.all_year
                end

                # Set value and BETWEEN
                sql = { value.to_sym => range }
              else
                sql = ((@filter_all_on || {}).merge(scoped_options[:filter_on] || {}))[key].gsub("?", "'#{value}'")
                sql = sql.gsub("%t", "#{table_name}")
              end

              sql_frag = send(:sanitize_sql_for_conditions, sql)

              case
                when sql_frag.nil? then nil
                when scoped_options[:conditions].nil? then scoped_options[:conditions] = sql_frag
                when scoped_options[:conditions].is_a?(Array) then scoped_options[:conditions][0].concat(" AND #{sql_frag}")
                when scoped_options[:conditions].is_a?(String) then scoped_options[:conditions].concat(" AND #{sql_frag}")
              end
            end
          end if filters.is_a?(Hash)

          base = self
          # chain named scopes
          scopes = Array(scoped_options[calculation])
          scopes.each do |scope|
            base = base.send(scope)
          end if scopes != [:all]
          stat_value = base.send(calculation, scoped_options[:column_name], sql_options(scoped_options))

          # cache stat value
          Rails.cache.write("#{self.name}#{method_name}#{filters}", stat_value, :expires_in => options[:cache_for]) if options[:cache_for]

          stat_value
        end
      end
    end

    # Defines a statistic using a block that has access to all other defined statistics
    #
    # EXAMPLE:
    # class MockModel < ActiveRecord::Base
    #   define_statistic "Basic Count", :count => :all
    #   define_statistic "Basic Sum", :sum => :all, :column_name => 'amount'
    #   define_calculated_statistic "Total Profit"
    #     defined_stats('Basic Sum') * defined_stats('Basic Count')
    #   end
    def define_calculated_statistic(name, &block)
      method_name = name.to_s.gsub(" ", "").underscore + "_stat"

      @statistics ||= {}
      @statistics[name] = method_name

      (class<<self; self; end).instance_eval do
        define_method(method_name) do |filters|
          @filters = filters
          yield
        end
      end
    end

    # returns an array containing the names/keys of all defined statistics
    def statistics_keys
      @statistics.keys
    end

    # Calculates all the statistics defined for this AR class and returns a hash with the values.
    # There is an optional parameter that is a hash of all values you want to filter by.
    #
    # EXAMPLE:
    # MockModel.statistics
    # MockModel.statistics(:user_type => 'registered', :user_status => 'active')
    def statistics(filters = {}, except = nil)
      (@statistics || {}).inject({}) do |stats_hash, stat|
        stats_hash[stat.first] = send(stat.last, filters) if stat.last != except
        stats_hash
      end
    end

    # returns a single statistic based on the +stat_name+ paramater passed in and
    # similarly to the +statistics+ method, it also can take filters.
    #
    # EXAMPLE:
    # MockModel.get_stat('Basic Count')
    # MockModel.get_stat('Basic Count', :user_type => 'registered', :user_status => 'active')
    def get_stat(stat_name, filters = {})
      send(@statistics[stat_name], filters) if @statistics[stat_name]
    end

    # to keep things DRY anything that all statistics need to be filterable by can be defined
    # seperatly using this method
    #
    # EXAMPLE:
    #
    # class MockModel < ActiveRecord::Base
    #   define_statistic "Basic Count", :count => :all
    #   define_statistic "Basic Sum", :sum => :all, :column_name => 'amount'
    #
    #   filter_all_stats_on(:user_id, "user_id = ?")
    # end
    def filter_all_stats_on(name, cond)
      @filter_all_on ||= {}
      @filter_all_on[name] = cond
    end

    private

      def defined_stats(name)
        get_stat(name, @filters)
      end

      def sql_options(options)
        Statistics::supported_calculations.each do |deletable|
          options.delete(deletable)
        end
        options.delete(:column_name)
        options.delete(:filter_on)
        options.delete(:cache_for)
        options
      end
  end
end

ActiveRecord::Base.send(:include, Statistics)
