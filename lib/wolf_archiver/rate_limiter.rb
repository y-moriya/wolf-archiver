# RateLimiter - リクエスト間隔制限
# 詳細仕様: spec/rate_limiter_spec.md を参照

module WolfArchiver
  class RateLimiter
    def initialize(wait_time, enabled: true)
      @wait_time = wait_time.to_f
      @enabled = enabled && @wait_time > 0
      @last_request_time = nil
    end

    def wait
      return unless @enabled
      
      if @last_request_time
        elapsed = current_time - @last_request_time
        remaining = @wait_time - elapsed
        
        sleep(remaining) if remaining > 0
      end
      
      @last_request_time = current_time
    end

    def elapsed_time
      return Float::INFINITY if @last_request_time.nil?
      current_time - @last_request_time
    end

    def remaining_wait_time
      return 0 unless @enabled
      return 0 if @last_request_time.nil?
      
      remaining = @wait_time - elapsed_time
      remaining > 0 ? remaining : 0
    end

    def enabled?
      @enabled
    end

    def reset
      @last_request_time = nil
    end

    private

    def current_time
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end
  end
end
