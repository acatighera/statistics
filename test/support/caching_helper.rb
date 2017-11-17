module CachingHelper
  def with_caching
    Rails.stubs(:cache).returns(
      ActiveSupport::Cache::MemoryStore.new(
        :expires_in => 1.minute
      )
    )
    yield
  ensure
    Rails.cache.clear
  end
end
