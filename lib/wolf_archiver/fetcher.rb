# Fetcher - HTTP通信
# 詳細仕様: spec/fetcher_spec.md を参照

require 'faraday'

module WolfArchiver
  class Fetcher
    def initialize(base_url, rate_limiter, timeout: 30, user_agent: nil)
      @base_url = base_url
      @rate_limiter = rate_limiter
      @timeout = timeout
      @user_agent = user_agent || default_user_agent
      
      setup_client
    end

    def fetch(path)
      url = build_url(path)
      @rate_limiter.wait
      
      response = @client.get(url)
      
      FetchResult.new(
        body: response.body,
        status: response.status,
        headers: response.headers,
        url: url
      )
    rescue Faraday::TimeoutError => e
      raise FetchError, "タイムアウト: #{url}", e
    rescue Faraday::ConnectionFailed => e
      raise FetchError, "接続失敗: #{url}", e
    rescue Faraday::Error => e
      raise FetchError, "HTTP取得エラー: #{e.message}", e
    end

    def fetch_binary(url)
      @rate_limiter.wait
      
      response = @client.get(url) do |req|
        req.options.timeout = @timeout
      end
      
      FetchResult.new(
        body: response.body.force_encoding('BINARY'),
        status: response.status,
        headers: response.headers,
        url: url
      )
    rescue => e
      raise FetchError, "バイナリ取得エラー: #{e.message}", e
    end

    private

    def setup_client
      @client = Faraday.new do |conn|
        conn.options.timeout = @timeout
        conn.options.open_timeout = 10
        
        conn.response :follow_redirects, limit: 5
        conn.headers['User-Agent'] = @user_agent
        conn.adapter Faraday.default_adapter
      end
    end

    def build_url(path)
      return path if path.start_with?('http://', 'https://')
      
      uri = URI.parse(@base_url)
      
      if path.start_with?('?')
        "#{uri.scheme}://#{uri.host}#{uri.port ? ":#{uri.port}" : ''}#{uri.path}#{path}"
      else
        File.join(@base_url, path)
      end
    end

    def default_user_agent
      "WolfArchiver/1.0 (Ruby/#{RUBY_VERSION})"
    end
  end

  class FetchResult
    attr_reader :body, :status, :headers, :url, :content_type
    
    def initialize(body:, status:, headers:, url:)
      @body = body
      @status = status
      @headers = headers
      @url = url
      @content_type = headers['content-type'] || headers['Content-Type'] || ''
    end

    def success?
      @status >= 200 && @status < 300
    end

    def text?
      @content_type.start_with?('text/') ||
      @content_type.include?('html') ||
      @content_type.include?('xml')
    end

    def binary?
      !text?
    end
  end
end
