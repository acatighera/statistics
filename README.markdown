# Statistics

This ActiverRecord plugin allows you to easily define and pull statistics for AR models. This plugin was built with reporting in mind.

## Installation
    script/plugin install git://github.com/acatighera/statistics.git

## Examples
#### Defining statistics is similar to defining named scopes:

    class Account < ActiveRecord::Base
      define_statistic :user_count, :count => :all
      define_statistic :average_age, :average => :all, :column_name => 'age'
      define_statistic :subscriber_count, :count => :all, :conditions => "subscription_opt_in = 1"
    end
    
    class Donations < ActiveRecord::Base
      define_statistic :total_donations, :sum => :all, :column_name => "amount"
    end

#### Actually pulling the numbers is simple:

#####for all stats

    Account.statistics                   # returns { :user_count => 120, :average_age => 28, :subscriber_count => 74 }

#####for a single stat

    Account.get_stat(‘:user_count’)      # returns 120

### Here are some additional benefits of using this plugin:

#### Easily Filter

Note: I found filtering to be an important part of reporting (ie. filtering by date). All filters are optional so even if you define them you don’t have to use them when pulling data. Using the `filter_all_stats_on` method and `:joins` options you can make things filterable by the same things which I found to be extremely useful.

    class Account < ActiveRecord::Base
      define_statistic :user_count, :count => :all, , :filter_on => { :state => 'state = ?', :created_after => 'DATE(created_at) > ?'}
      define_statistic :subscriber_count, :count => :all, :conditions => "subscription_opt_in = true"
      
      filter_all_stats_on(:account_type, "account_type = ?")
    end

    Account.statistics(:account_type => 'non-admin')
    Account.get_stat(:user_count,  :account_type => 'non-admin',  :created_after => ‘2009-01-01’, :state => 'NY')

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
