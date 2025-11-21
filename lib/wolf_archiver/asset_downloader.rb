# AssetDownloader - アセットダウンロード
# 詳細仕様: spec/asset_downloader_spec.md を参照

module WolfArchiver
  class AssetDownloader
    def initialize(fetcher, storage, path_mapper, encoding = 'UTF-8')
      @logger = LoggerConfig.logger('AssetDownloader')
      @fetcher = fetcher
      @storage = storage
      @path_mapper = path_mapper
      @encoding = encoding
      @css_discovered_urls = []
      @logger.info("AssetDownloader初期化: encoding=#{encoding}")
    end

    def download(assets)
      @logger.info("アセットダウンロード開始: 合計#{assets.size}件")
      succeeded = []
      failed = []
      skipped = []
      @css_discovered_urls = []

      unique_assets = deduplicate_assets(assets)
      @logger.debug("重複除去後: #{unique_assets.size}件")

      # First pass: download all assets including CSS/JS
      unique_assets.each do |asset|
        result = download_single(asset)

        if result == :skipped
          skipped << asset.url
          @logger.debug("スキップ: #{asset.url}")
        elsif result
          succeeded << result
          @logger.debug("ダウンロード成功: #{asset.url}")
        else
          failed << { url: asset.url, error: 'Unknown error' }
          @logger.warn("ダウンロード失敗: #{asset.url}")
        end
      rescue StandardError => e
        failed << { url: asset.url, error: e.message, type: asset.type }
        @logger.error("ダウンロードエラー: #{asset.url} - #{e.message}")
      end

      # Second pass: download images discovered in CSS files
      if @css_discovered_urls.any?
        @logger.info("CSS内で発見された画像: #{@css_discovered_urls.size}件")
        css_image_assets = @css_discovered_urls.map do |url|
          Asset.new(url: url, type: :image, element: nil, attribute: nil)
        end

        deduplicated_css_images = deduplicate_assets(css_image_assets)
        @logger.debug("CSS画像重複除去後: #{deduplicated_css_images.size}件")

        deduplicated_css_images.each do |asset|
          result = download_binary_asset(asset)

          if result == :skipped
            skipped << asset.url
          elsif result
            succeeded << result
          else
            failed << { url: asset.url, error: 'Unknown error', type: :css_image }
          end
        rescue StandardError => e
          failed << { url: asset.url, error: e.message, type: :css_image }
          @logger.error("CSS画像ダウンロードエラー: #{asset.url} - #{e.message}")
        end
      end

      @logger.info("アセットダウンロード完了: 成功=#{succeeded.size}, 失敗=#{failed.size}, スキップ=#{skipped.size}")
      DownloadResult.new(succeeded: succeeded, failed: failed, skipped: skipped)
    end

    def download_single(asset)
      file_path = @path_mapper.url_to_path(asset.url)

      return nil unless file_path

      return :skipped if @storage.exist?(file_path)

      case asset.type
      when :css
        download_css_asset(asset, file_path)
      when :js
        download_js_asset(asset, file_path)
      else
        download_binary_asset(asset, file_path)
      end
    rescue FetchError
      # 404などのHTTPエラーはnilを返す（failedに追加される）
      nil
    rescue StorageError => e
      raise AssetDownloaderError, "アセット保存失敗: #{e.message}"
    end

    private

    def download_css_asset(asset, file_path)
      @logger.debug("CSSダウンロード開始: #{asset.url}")
      result = @fetcher.fetch_binary(asset.url)

      return nil unless result.success?

      # エンコーディング変換
      utf8_content = EncodingConverter.to_utf8(result.body, @encoding)
      @logger.debug("CSSエンコーディング変換完了: #{@encoding} => UTF-8")

      # CSS内の画像URL抽出
      base_url = asset.url
      discovered_urls = extract_urls_from_css(utf8_content, base_url)
      if discovered_urls.any?
        @logger.info("CSS内で#{discovered_urls.size}件の画像URLを発見: #{asset.url}")
        @css_discovered_urls.concat(discovered_urls)
      end

      # CSS内のURLを相対パスに書き換え
      rewritten_content = rewrite_css_urls(utf8_content, asset.url, file_path)

      # UTF-8テキストとして保存
      @storage.save(file_path, rewritten_content)
      @logger.info("CSS保存完了: #{file_path}")
      file_path
    end

    def download_js_asset(asset, file_path)
      @logger.debug("JSダウンロード開始: #{asset.url}")
      result = @fetcher.fetch_binary(asset.url)

      return nil unless result.success?

      # エンコーディング変換
      utf8_content = EncodingConverter.to_utf8(result.body, @encoding)
      @logger.debug("JSエンコーディング変換完了: #{@encoding} => UTF-8")

      # UTF-8テキストとして保存
      @storage.save(file_path, utf8_content)
      @logger.info("JS保存完了: #{file_path}")
      file_path
    end

    def download_binary_asset(asset, file_path = nil)
      file_path ||= @path_mapper.url_to_path(asset.url)

      return nil unless file_path

      return :skipped if @storage.exist?(file_path)

      result = @fetcher.fetch_binary(asset.url)

      return nil unless result.success?

      @storage.save_binary(file_path, result.body)
      file_path
    end

    def extract_urls_from_css(css_content, base_url)
      urls = []

      # url(...)パターンを抽出 - Parserと同じロジック
      css_content.scan(/url\s*\(\s*(['"]?)(.+?)\1\s*\)/i) do |_, url|
        url = url.strip
        next if url.empty? || url.start_with?('data:')

        absolute_url = resolve_url(url, base_url)
        urls << absolute_url if absolute_url
      end

      urls.uniq
    end

    def resolve_url(url, base_url)
      return nil if url.nil? || url.empty?

      # 既に絶対URLの場合
      return remove_fragment(url) if url.start_with?('http://', 'https://')

      # プロトコル相対URL（//example.com/...）
      if url.start_with?('//')
        base_uri = Addressable::URI.parse(base_url)
        return remove_fragment("#{base_uri.scheme}:#{url}")
      end

      # 相対URLを解決
      base_uri = Addressable::URI.parse(base_url)
      resolved_uri = base_uri.join(url)
      resolved_uri.fragment = nil
      resolved_uri.to_s
    rescue Addressable::URI::InvalidURIError
      @logger.warn("AssetDownloader: URL解決失敗 #{url}")
      nil
    end

    def remove_fragment(url)
      uri = Addressable::URI.parse(url)
      uri.fragment = nil
      uri.to_s
    rescue StandardError
      url
    end

    def rewrite_css_urls(css_content, css_url, css_file_path)
      # CSS内のurl(...)を相対パスに書き換える
      css_content.gsub(/url\s*\(\s*(['"]?)(.+?)\1\s*\)/i) do |match|
        quote = Regexp.last_match(1)
        url = Regexp.last_match(2).strip

        # data: URLやフラグメントはそのまま
        if url.start_with?('data:', '#')
          match
        else
          # 相対URLも含めて絶対URLに解決
          absolute_url = resolve_url(url, css_url)
          next match unless absolute_url

          # ローカルパスに変換
          local_path = @path_mapper.url_to_path(absolute_url)
          next match unless local_path

          # CSS位置から画像への相対パスを計算
          css_dir = File.dirname(css_file_path)
          relative_path = Pathname.new(local_path).relative_path_from(Pathname.new(css_dir)).to_s

          # パス区切りを/に統一（Windows対応）
          relative_path = relative_path.tr('\\', '/')

          "url(#{quote}#{relative_path}#{quote})"
        end
      end
    end

    def deduplicate_assets(assets)
      seen_urls = Set.new
      unique_assets = []

      assets.each do |asset|
        unless seen_urls.include?(asset.url)
          seen_urls.add(asset.url)
          unique_assets << asset
        end
      end

      unique_assets
    end
  end

  class DownloadResult
    attr_reader :succeeded, :failed, :skipped, :total

    def initialize(succeeded:, failed:, skipped:)
      @succeeded = succeeded
      @failed = failed
      @skipped = skipped
      @total = succeeded.size + failed.size + skipped.size
    end

    def success_rate
      return 1.0 if @total == 0

      @succeeded.size.to_f / (@succeeded.size + @failed.size)
    end

    def summary
      <<~SUMMARY
        アセットダウンロード結果:
          成功: #{@succeeded.size}件
          失敗: #{@failed.size}件
          スキップ: #{@skipped.size}件
          合計: #{@total}件
          成功率: #{(success_rate * 100).round(1)}%
      SUMMARY
    end
  end
end
