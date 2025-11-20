# AssetDownloader - アセットダウンロード
# 詳細仕様: spec/asset_downloader_spec.md を参照

module WolfArchiver
  class AssetDownloader
    def initialize(fetcher, storage, path_mapper)
      @logger = LoggerConfig.logger('AssetDownloader')
      @fetcher = fetcher
      @storage = storage
      @path_mapper = path_mapper
      @logger.info("AssetDownloader初期化")
    end

    def download(assets)
      @logger.info("アセットダウンロード開始: 合計#{assets.size}件")
      succeeded = []
      failed = []
      skipped = []
      
      unique_assets = deduplicate_assets(assets)
      @logger.debug("重複除去後: #{unique_assets.size}件")
      
      unique_assets.each do |asset|
        begin
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
        rescue => e
          failed << { url: asset.url, error: e.message, type: asset.type }
          @logger.error("ダウンロードエラー: #{asset.url} - #{e.message}")
        end
      end
      
      @logger.info("アセットダウンロード完了: 成功=#{succeeded.size}, 失敗=#{failed.size}, スキップ=#{skipped.size}")
      DownloadResult.new(succeeded: succeeded, failed: failed, skipped: skipped)
    end

    def download_single(asset)
      file_path = @path_mapper.url_to_path(asset.url)
      
      return nil unless file_path
      
      if @storage.exist?(file_path)
        return :skipped
      end
      
      begin
        result = @fetcher.fetch_binary(asset.url)
        
        unless result.success?
          return nil
        end
        
        @storage.save_binary(file_path, result.body)
        file_path
      rescue FetchError => e
        # 404などのHTTPエラーはnilを返す（failedに追加される）
        return nil
      rescue StorageError => e
        raise AssetDownloaderError, "アセット保存失敗: #{e.message}"
      end
    end

    private

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
