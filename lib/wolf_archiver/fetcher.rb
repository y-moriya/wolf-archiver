# Fetcher - HTTP通信
# 詳細仕様: spec/fetcher_spec.md を参照

require 'faraday'

module WolfArchiver
  class Fetcher
    def initialize(base_url, rate_limiter, timeout: 30, user_agent: nil, max_retries: 5)
      @logger = LoggerConfig.logger('Fetcher')
      @base_url = base_url
      @rate_limiter = rate_limiter
      @timeout = timeout
      @user_agent = user_agent || default_user_agent
      @max_retries = max_retries

      @logger.info("Fetcher初期化: base_url=#{base_url}, timeout=#{timeout}, max_retries=#{max_retries}")
      setup_client
    end

    def fetch(path)
      url = build_url(path)
      retries = 0

      loop do
        @logger.debug("HTTPリクエスト開始: #{url}")
        @rate_limiter.wait

        begin
          response = @client.get(url)
          @logger.debug("HTTPレスポンス: status=#{response.status}, url=#{url}")

          if response.status == 503
            if retries < @max_retries
              retries += 1
              @logger.warn("503 Service Unavailable: #{url} - リトライ #{retries}/#{@max_retries}")
              next
            else
              @logger.error("サーバーエラー (503): #{url} - リトライ回数超過")
              raise FetchError.new("サーバーエラー (503): #{url} - リトライ回数超過", url: url, status: 503)
            end
          end

          # エラーステータスコードのチェック
          case response.status
          when 404
            @logger.warn("ページが見つかりません: #{url}")
            raise FetchError.new("ページが見つかりません: #{url}", url: url, status: 404)
          when 500..599
            @logger.error("サーバーエラー (#{response.status}): #{url}")
            raise FetchError.new("サーバーエラー (#{response.status}): #{url}", url: url, status: response.status)
          end

          return FetchResult.new(
            body: response.body,
            status: response.status,
            headers: response.headers,
            url: url
          )
        rescue URI::InvalidURIError, Addressable::URI::InvalidURIError => e
          @logger.error("不正なURL: #{url} - #{e.message}")
          raise FetchError.new("不正なURL: #{url}", url: url, original_error: e)
        rescue Faraday::TimeoutError => e
          @logger.error("タイムアウト: #{url}")
          raise FetchError.new("タイムアウト: #{url}", url: url, original_error: e)
        rescue Faraday::ConnectionFailed => e
          @logger.error("接続失敗: #{url} - #{e.message}")
          raise FetchError.new("接続失敗: #{url}", url: url, original_error: e)
        rescue Faraday::Error => e
          @logger.error("HTTP取得エラー: #{e.message}")
          raise FetchError.new("HTTP取得エラー: #{e.message}", url: url, original_error: e)
        end
      end
    end

    def fetch_binary(url)
      retries = 0

      loop do
        @logger.debug("バイナリ取得開始: #{url}")
        @rate_limiter.wait

        begin
          response = @client.get(url) do |req|
            req.options.timeout = @timeout
          end

          @logger.debug("バイナリ取得完了: status=#{response.status}, size=#{response.body.bytesize} bytes")

          if response.status == 503
            if retries < @max_retries
              retries += 1
              @logger.warn("バイナリ取得 503エラー: #{url} - リトライ #{retries}/#{@max_retries}")
              next
            else
              @logger.error("バイナリ取得エラー: サーバーエラー (503): #{url} - リトライ回数超過")
              raise FetchError.new("バイナリ取得エラー: サーバーエラー (503): #{url} - リトライ回数超過", url: url, status: 503)
            end
          end

          # エラーステータスコードのチェック
          case response.status
          when 404
            @logger.warn("バイナリ取得エラー: ページが見つかりません: #{url}")
            raise FetchError.new("バイナリ取得エラー: ページが見つかりません: #{url}", url: url, status: 404)
          when 500..599
            @logger.error("バイナリ取得エラー: サーバーエラー (#{response.status}): #{url}")
            raise FetchError.new("バイナリ取得エラー: サーバーエラー (#{response.status}): #{url}", url: url, status: response.status)
          end

          return FetchResult.new(
            body: response.body.dup.force_encoding('BINARY'),
            status: response.status,
            headers: response.headers,
            url: url
          )
        rescue Faraday::TimeoutError => e
          @logger.error("バイナリ取得エラー: タイムアウト - #{url}")
          raise FetchError.new('バイナリ取得エラー: タイムアウト', url: url, original_error: e)
        rescue Faraday::ConnectionFailed => e
          @logger.error("バイナリ取得エラー: 接続失敗 - #{url}")
          raise FetchError.new('バイナリ取得エラー: 接続失敗', url: url, original_error: e)
        rescue Faraday::Error => e
          @logger.error("バイナリ取得エラー: #{e.message}")
          raise FetchError.new("バイナリ取得エラー: #{e.message}", url: url, original_error: e)
        rescue StandardError => e
          @logger.error("バイナリ取得エラー: #{e.message}")
          raise FetchError.new("バイナリ取得エラー: #{e.message}", url: url, original_error: e)
        end
      end
    end

    private

    def setup_client
      @client = Faraday.new do |conn|
        conn.options.timeout = @timeout
        conn.options.open_timeout = 10

        # Faraday 2.xではリダイレクトは自動的に処理される
        # 必要に応じて手動でリダイレクトを処理
        conn.headers['User-Agent'] = @user_agent
        conn.adapter Faraday.default_adapter
      end
    end

    def build_url(path)
      return path if path.start_with?('http://', 'https://')

      uri = URI.parse(@base_url)

      if path.empty?
        @base_url
      elsif path.start_with?('?')
        port_part = uri.port && uri.port != 80 && uri.port != 443 ? ":#{uri.port}" : ''
        "#{uri.scheme}://#{uri.host}#{port_part}#{uri.path}#{path}"
      else
        File.join(@base_url, path)
      end
    end

    def default_user_agent
      "WolfArchiver/1.0 (Ruby/#{RUBY_VERSION})"
    end
  end

  class FetchError < WolfArchiverError
    attr_reader :url, :status, :original_error

    def initialize(message, url: nil, status: nil, original_error: nil)
      @url = url
      @status = status
      @original_error = original_error
      super(message)
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
