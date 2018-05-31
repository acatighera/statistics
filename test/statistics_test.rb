require 'test/unit'

require 'rubygems'
gem 'activerecord', '>= 1.15.4.7794'
gem 'mocha', '>= 0.9.0'
require 'active_record'
require 'active_support'
require 'mocha/setup'
require 'byebug'
require 'rails'

require_relative "../init"
require_relative "./support/caching_helper"

ActiveRecord::Base.establish_connection(:adapter => "sqlite3", :database => ":memory:")

load "./db/schema.rb"
class StatisticsTest < Test::Unit::TestCase
  include CachingHelper

  class BasicModel < ActiveRecord::Base
    define_statistic :basic_num, :count => :all
  end

  class MockModel < ActiveRecord::Base
    define_statistic "Basic Count", :count => :all
    define_statistic :symbol_count, :count => :all
    define_statistic "Basic Sum", :sum => :all, :column_name => 'amount'
    define_statistic "Chained Scope Count", :count => [:all, :named_scope]
    define_statistic "Default Filter", :count => :all
    define_statistic "Custom Filter", :count => :all, :filter_on => { :channel => 'channel = ?', :start_date => 'DATE(created_at) > ?', :blah => 'blah = ?' }
    define_statistic "Cached", :count => :all, :filter_on => { :channel => 'channel = ?', :blah => 'blah = ?' }, :cache_for => 1.second
    define_statistic "Dynamic Cached", :count => :all, :filter_on => { :channel => 'channel = ?', :blah => 'blah = ?' }, :cache_for => lambda { |filter_on| filter_on[:channel] == "chan5" ? 1.second : 0.seconds }

    define_calculated_statistic "Total Amount" do
      defined_stats('Basic Sum') * defined_stats('Basic Count')
    end

    filter_all_stats_on(:user_id, "user_id = ?")
  end

  def test_basic
    BasicModel.expects(:basic_num_stat).returns(1)
    assert_equal({ :basic_num => 1 }, BasicModel.statistics)
  end

  def test_statistics
    MockModel.expects(:basic_count_stat).returns(2)
    MockModel.expects(:symbol_count_stat).returns(2)
    MockModel.expects(:basic_sum_stat).returns(27)
    MockModel.expects(:chained_scope_count_stat).returns(4)
    MockModel.expects(:default_filter_stat).returns(5)
    MockModel.expects(:custom_filter_stat).returns(3)
    MockModel.expects(:cached_stat).returns(9)
    MockModel.expects(:dynamic_cached_stat).returns(7)
    MockModel.expects(:total_amount_stat).returns(54)

    ["Basic Count",
     :symbol_count,
     "Basic Sum",
     "Chained Scope Count",
     "Default Filter",
     "Custom Filter",
     "Cached",
     "Dynamic Cached",
     "Total Amount"].each do |key|
       assert MockModel.statistics_keys.include?(key)
     end

     assert_equal({ "Basic Count" => 2,
                    :symbol_count => 2,
                    "Basic Sum" => 27,
                    "Chained Scope Count" => 4,
                    "Default Filter" => 5,
                    "Custom Filter" => 3,
                    "Cached" => 9,
                    "Dynamic Cached" => 7,
                    "Total Amount" => 54 }, MockModel.statistics)
  end

  def test_get_stat
    MockModel.expects(:count).with(:id).returns(3)
    assert_equal 3, MockModel.get_stat("Basic Count")

    object = stub.tap { |obj| obj.stubs(:count).with(:id).returns(4) }
    MockModel.expects(:where).with("user_id = '54321'").returns(object)
    assert_equal 4, MockModel.get_stat("Basic Count", :user_id => 54321)
  end

  def test_basic_stat
    MockModel.expects(:count).with(:id).returns(3)
    assert_equal 3, MockModel.basic_count_stat({})

    MockModel.expects(:sum).with("amount").returns(31)
    assert_equal 31, MockModel.basic_sum_stat({})
  end

  def test_chained_scope_stat
    MockModel.expects(:all).returns(MockModel)
    MockModel.expects(:named_scope).returns(MockModel)
    MockModel.expects(:count).with(:id).returns(5)
    assert_equal 5, MockModel.chained_scope_count_stat({})
  end

  def test_calculated_stat
    MockModel.expects(:basic_count_stat).returns(3)
    MockModel.expects(:basic_sum_stat).returns(33)

    assert_equal 99, MockModel.total_amount_stat({})

    MockModel.expects(:basic_count_stat).with(:user_id => 5).returns(2)
    MockModel.expects(:basic_sum_stat).with(:user_id => 5).returns(25)

    assert_equal 50, MockModel.total_amount_stat({:user_id => 5})

    MockModel.expects(:basic_count_stat).with(:user_id => 6).returns(3)
    MockModel.expects(:basic_sum_stat).with(:user_id => 6).returns(60)

    assert_equal 180, MockModel.total_amount_stat({:user_id => 6})
  end

  def test_default_filter_stat
    MockModel.expects(:count).with(:id).returns(8)
    assert_equal 8, MockModel.default_filter_stat({})

    object = stub.tap { |obj| obj.stubs(:count).with(:id).returns(2) }
    MockModel.expects(:where).with("user_id = '12345'").returns(object)
    assert_equal 2, MockModel.default_filter_stat( :user_id => '12345' )
  end

  def test_custom_filter_stat
    MockModel.expects(:count).with(:id).returns(6)
    assert_equal 6, MockModel.custom_filter_stat({})

    object = stub.tap { |obj| obj.stubs(:count).with(:id).returns(3) }
    MockModel.expects(:where).with("channel = 'chan5' AND DATE(created_at) > '#{Date.today.to_s(:db)}'").returns(object)
    assert_equal 3, MockModel.custom_filter_stat(:channel => 'chan5', :start_date => Date.today.to_s(:db))
  end

  def test_cached_stat
    with_caching do
      object = stub.tap { |obj| obj.stubs(:count).with(:id).returns(6) }
      MockModel.expects(:where).returns(object)
      assert_equal 6, MockModel.cached_stat({:channel => 'chan5'})

      MockModel.expects(:where).never
      assert_equal 6, MockModel.cached_stat({:channel => 'chan5'})
      sleep(1)
      object = stub.tap { |obj| obj.stubs(:count).with(:id).returns(8) }
      MockModel.expects(:where).returns(object)
      assert_equal 8, MockModel.cached_stat({:channel => 'chan5'})
    end
  end

  def test_dynamic_cached_stat
    with_caching do
      object = stub.tap { |obj| obj.stubs(:count).with(:id).returns(6) }
      MockModel.expects(:where).returns(object)
      assert_equal 6, MockModel.dynamic_cached_stat({:channel => 'chan5'})

      MockModel.expects(:where).never
      assert_equal 6, MockModel.dynamic_cached_stat({:channel => 'chan5'})

      object = stub.tap { |obj| obj.stubs(:count).with(:id).returns(7) }
      MockModel.expects(:where).returns(object)
      assert_equal 7, MockModel.dynamic_cached_stat({:channel => 'chan6'})
    end
  end

  def test_bypass_cached_stat
    with_caching do
      object = stub.tap { |obj| obj.stubs(:count).with(:id).returns(6) }
      MockModel.expects(:where).returns(object)
      assert_equal 6, MockModel.get_stat!("Dynamic Cached", {:channel => 'chan5'})

      object = stub.tap { |obj| obj.stubs(:count).with(:id).returns(8) }
      MockModel.expects(:where).returns(object)
      assert_equal 8, MockModel.get_stat!("Dynamic Cached", {:channel => 'chan5'})
    end
  end
end
