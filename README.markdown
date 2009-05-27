# Statistics

This ActiverRecord plugin allows you to easily define and pull statistics for AR models. This plugin was built with reporting in mind.

## Installation
    script/plugin install git://github.com/acatighera/statistics.git

## Examples
#### Defining statistics is similar to defining named scopes:

    class Account < ActiveRecord::Base
      define_statistic "User Count", :count => :all
      define_statistic "Average Age", :average => :all, :column_name => 'age'
      define_statistic "Subcriber Count", :count => :all, :conditions => "subscription_opt_in = 1"
    end
    
    class Donations < ActiveRecord::Base
      define_statistic "Total Donations", :sum => :all, :column_name => "amount"
    end

#### Actually pulling the numbers is simple:

#####for all stats

    Account.statistics # returns { 'User Count' => 120, 'Average Age' => 28, 'Subscriber Count' => 74 }

#####for a single stat

    Account.get_stat(‘User Count’) # returns 120

### Here are some additional benefits of using this plugin:

#### Easily Filter

Note: I found filtering to be an important part of reporting (ie. filtering by date). All filters are optional so even if you define them you don’t have to use them when pulling data. Using the `filter_all_stats_on` method and `:joins` options you can make things filterable by the same things which I found to be extremely useful.

    class Account < ActiveRecord::Base
      define_statistic "User Count", :count => :all, , :filter_on => { :state => 'state = ?', :created_after => 'DATE(created_at) > ?'}
      define_statistic "Subcriber Count", :count => :all, :conditions => "subscription_opt_in = true"
      
      filter_all_stats_on(:account_type, "account_type = ?")
    end

    Account.statistics(:account_type => 'non-admin')
    Account.get_stat(‘User Count’,  :account_type => 'non-admin',  :created_after => ‘2009-01-01’, :state => 'NY')

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
      
      define_statistic "User Count", :count => :all
      define_statistic "Total Donations", :sum => :all, :column_name => 'donations.amount', :joins => :donations
      
      define_calculated_statistic "Average Donation per User" do
        defined_stats('Total Donations') / defined_stats('User Count')
      end
      
      filter_all_stats_on(:account_type, "account_type = ?")
      filter_all_stats_on(:state, "state = ?")
      filter_all_stats_on(:created_after, "DATE(created_at) > ?")
    end
    

Pulling stats for calculated metrics is the same as for regular statistics. They also work with filters like regular statistics! 

    Account.get_stat('Average Donation Per User', :account_type => 'non-admin', :state => 'NY')
    Account.get_stat('Average Donation Per User', :created_after => '2009-01-01')

#### Reuse scopes you already have defined

You can reuse the code you have written to do reporting.

    class Account < ActiveRecord::Base
      has_many :posts
      
      named_scope :not_admins, :conditions => “account_type = ‘non-admin’”
      named_scope :accounts_with_posts, :joins => :posts
      
      define_statistic "Active Users Count", :count => [:not_admins, :accounts_with_posts]
    end

#### Accepts all ActiveRecord::Calculations options

The `:conditions` and `:joins` options are all particularly useful

    class Account < ActiveRecord::Base
      define_statistic "Active Accounts With Posts", :count => :all, :joins => :posts, :conditions => "status = 'active'"
    end

###### Copyright (c) 2009 Alexandru Catighera, released under MIT license
