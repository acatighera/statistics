# Statistics

This ActiverRecord plugin allows you to easily define and pull statistics for AR models. This plugin was built with reporting in mind.

## ANNOUCEMENT

I need this specific behaviour for collect staticitics in time ranges on
specific field (created_at, payed_at etc..). If you decide to use my
modification:

    gem 'statistics', github: "tam-vo/statistics"

## Installation
    gem install statistics

## Run tests
    bundle exec ruby test/statistics_test.rb

## Usage: retrieve statistics value

Get statistics value (use cache value if available)

    Account.get_stat(:user_count)

Get statistics value force to recalculate (bypass cache)

    Account.get_stat!(:user_count)

Get collection from statistics query

    Account.stat_collection(:user_count)

Get SQL query from statistics query

    Account.stat_collection(:user_count).to_sql

## Examples
#### Defining statistics is similar to defining named scopes. Strings and symbols both work as names.

    class Account < ActiveRecord::Base
      define_statistic :user_count, :count => :all
      define_statistic :average_age, :average => :all, :column_name => 'age'
      define_statistic 'subscriber count', :count => :all, :conditions => "subscription_opt_in = 1"
    end

    class Donations < ActiveRecord::Base
      define_statistic :total_donations, :sum => :all, :column_name => "amount"
    end

#### Actually pulling the numbers is simple:

##### for all stats

    Account.statistics                   # returns { :user_count => 120, :average_age => 28, 'subscriber count' => 74 }

##### for a single stat

    Account.get_stat(:user_count)      # returns 120

### Here are some additional benefits of using this plugin:

#### Easily Filter

Note: I found filtering to be an important part of reporting (ie. filtering by date). All filters are optional so even if you define them you don’t have to use them when pulling data. Using the `filter_all_stats_on` method and `:joins` options you can make things filterable by the same things which I found to be extremely useful.

    class Account < ActiveRecord::Base
      define_statistic :user_count, :count => :all, :filter_on => { :state => 'state = ?', :created_after => 'DATE(created_at) > ?'}
      define_statistic :subscriber_count, :count => :all, :conditions => "subscription_opt_in = true"

      filter_all_stats_on(:account_type, "account_type = ?")
    end

    Account.statistics(:account_type => 'non-admin')
    Account.get_stat(:user_count,  :account_type => 'non-admin',  :created_after => ‘2009-01-01’, :state => 'NY')

    # NOTE: filters are optional (ie. no filters will be applied if none are passed in)
    Account.get_stat(:user_count)

    3 ways to work

    a. Default SQL query builder:

filter_on: { :account_type => :default, :created_at => :default }

Account.get_stat(:user_count, :account_type => 'non-admin', created_at: Time.now.all_week)

    b. Day Range SQL query builder:

filter_on: { :account_type => :default, :created_at => :day_range }

Account.get_stat(:user_count, :account_type => 'non-admin', created_at: Date.current)

    c. Customise SQL

filter_on: { :account_type => 'account_type = ?' }

Account.get_stat(:user_count,  :account_type => 'non-admin')

    d. Range

You will be no able to use named filters:

    [ :range_today :range_week, :range_month and :range_year ]

If you want to use it here is how:

    class User < ActiveRecord::Base
      define_statistic :user_count, :count => :all
    end

    # I want count of user registrated last week and month
    last_week = User.get_stat(:user_count, :range_week => :created_at)
    last_month = User.get_stat(:user_count, :range_month => :created_at)


Allways use: :range_week => :created_at

#### Caching

This is a new feature that uses `Rails.cache`. You can cache certain statistics for a specified amount of time (see below). By default caching is disabled if you do not pass in the `:cache_for` option. It is also important to note that caching is scoped by filters, there is no way around this since different filters produce different values.
    class Account < ActiveRecord::Base
      define_statistic :user_count, :count => :all, :cache_for => 30.minutes, :filter_on { :state => 'state = ?' }
    end

    Account.statistics(:state => 'NY') # This call generates a SQL query

    Account.statistics(:state => 'NY') # This call and subsequent calls for the next 30 minutes will use the cached value

    Account.statistics(:state => 'PA') # This call generates a SQL query because the user count for NY and PA could be different (and probably is)

Note: If you want Rails.cache to work properly, you need to use mem_cache_store in your rails enviroment file (ie. `config.cache_store = :mem_cache_store` in your enviroment.rb file).

#### Standardized

All ActiveRecord classes now respond to `statistics` and `get_stat` methods

    all_stats = []
    [ Account, Post, Comment ].each do |ar|
      all_stats << ar.statistics
    end

#### Calculated statistics (DRY)

You can define calculated metrics in order to perform mathematical calculations on one or more defined statistics.

    class Account < ActiveRecord::Base
      has_many :donations

      define_statistic :user_count, :count => :all
      define_statistic :total_donations, :sum => :all, :column_name => 'donations.amount', :joins => :donations

      define_calculated_statistic :average_donation_per_user do
        defined_stats(:total_donations) / defined_stats(:user_count)
      end

      filter_all_stats_on(:account_type, "account_type = ?")
      filter_all_stats_on(:state, "state = ?")
      filter_all_stats_on(:created_after, "DATE(created_at) > ?")
    end


Pulling stats for calculated metrics is the same as for regular statistics. They also work with filters like regular statistics!

    Account.get_stat(:average_donation_per_user, :account_type => 'non-admin', :state => 'NY')
    Account.get_stat(:average_donation_per_user, :created_after => '2009-01-01')

#### Reuse scopes you already have defined

You can reuse the code you have written to do reporting.

    class Account < ActiveRecord::Base
      has_many :posts

      named_scope :not_admins, :conditions => “account_type = ‘non-admin’”
      named_scope :accounts_with_posts, :joins => :posts

      define_statistic :active_users_count, :count => [:not_admins, :accounts_with_posts]
    end

#### Accepts all ActiveRecord::Calculations options

The `:conditions` and `:joins` options are all particularly useful

    class Account < ActiveRecord::Base
      has_many :posts

      define_statistic :active_users_count, :count => :all, :joins => :posts, :conditions => "account_type = 'non-admin'"
    end

###### Copyright (c) 2009 Alexandru Catighera, released under MIT license
