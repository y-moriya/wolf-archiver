# WolfArchiver - メインクラス
# 詳細仕様: spec/wolf_archiver_spec.md を参照

require 'tty-progressbar'

module WolfArchiver
  class WolfArchiver
    def initialize(site_name:, config_path:, output_dir:)
      @site_name = site_name
      @output_dir = output_dir
      
      @config_loader = ConfigLoader.new(config_path)
      @site_config = @config_loader.site(site_name)
      
      @downloaded_paths = Set.new
      @start_time = Time.now
      @end_time = nil
      
      @stats = {
        pages: { total: 0, succeeded: 0, failed: 0 },
        assets: { total: 0, succeeded: 0, failed: 0, skipped: 0 }
      }
      
      setup_modules
    end

    def run(village_ids: nil, user_ids: nil, auto_discover: false,
            users_only: false, villages_only: false, static_only: false)
      pages = determine_pages(
        village_ids: village_ids,
        user_ids: user_ids,
        auto_discover: auto_discover,
        users_only: users_only,
        villages_only: villages_only,
        static_only: static_only
      )
      
      if pages.empty?
        puts "ダウンロード対象がありません"
        return build_result
      end
      
      puts "ダウンロード対象: #{pages.size}ページ"
      process_pages(pages)
      
      @end_time = Time.now
      result = build_result
      
      puts "=" * 60
      puts result.summary
      puts "=" * 60
      
      result
    end

    private

    def setup_modules
      site_output_dir = File.join(@output_dir, @site_name)
      @storage = Storage.new(site_output_dir)
      
      @rate_limiter = RateLimiter.new(
        @site_config.actual_wait_time,
        enabled: !@site_config.localhost?
      )
      
      @fetcher = Fetcher.new(
        @site_config.base_url,
        @rate_limiter,
        timeout: 30
      )
      
      base_domain = URI.parse(@site_config.base_url).host
      @parser = Parser.new(@site_config.base_url)
      
      @path_mapper = PathMapper.new(
        @site_config.base_url,
        @site_config.path_mapping,
        @site_config.assets
      )
      
      @asset_downloader = AssetDownloader.new(
        @fetcher,
        @storage,
        @path_mapper
      )
    end

    def determine_pages(village_ids: nil, user_ids: nil, auto_discover: false,
                        users_only: false, villages_only: false, static_only: false)
      pages = []
      
      if static_only
        pages.concat(build_static_pages)
        return pages
      end
      
      if users_only
        uids = user_ids || (auto_discover ? discover_user_ids : [])
        pages.concat(build_user_pages(uids))
        return pages
      end
      
      if villages_only
        vids = village_ids || (auto_discover ? discover_village_ids : [])
        pages.concat(build_village_pages(vids))
        return pages
      end
      
      pages << build_index_page
      
      if auto_discover || village_ids
        vids = village_ids || discover_village_ids
        pages.concat(build_village_pages(vids))
      end
      
      if auto_discover || user_ids
        uids = user_ids || discover_user_ids
        pages.concat(build_user_pages(uids))
      end
      
      pages.concat(build_static_pages)
      pages
    end

    def build_index_page
      query = @site_config.pages[:index]
      { url: "#{@site_config.base_url}#{query}", path: 'index.html' }
    end

    def build_village_pages(village_ids)
      pages = []
      
      if query = @site_config.pages[:village_list]
        pages << { url: "#{@site_config.base_url}#{query}", path: 'village_list.html' }
      end
      
      village_ids.each do |village_id|
        (1..5).each do |day|
          query = @site_config.pages[:village]
            .gsub('%{village_id}', village_id.to_s)
            .gsub('%{date}', day.to_s)
          
          url = "#{@site_config.base_url}#{query}"
          path = "villages/#{village_id}/day#{day}.html"
          
          pages << { url: url, path: path }
        end
      end
      
      pages
    end

    def build_user_pages(user_ids)
      pages = []
      
      if query = @site_config.pages[:user_list]
        pages << { url: "#{@site_config.base_url}#{query}", path: 'users/index.html' }
      end
      
      user_ids.each do |user_id|
        query = @site_config.pages[:user].gsub('%{user_id}', user_id.to_s)
        url = "#{@site_config.base_url}#{query}"
        path = "users/#{user_id}.html"
        
        pages << { url: url, path: path }
      end
      
      pages
    end

    def build_static_pages
      pages = []
      
      @site_config.pages[:static]&.each do |query|
        url = "#{@site_config.base_url}#{query}"
        path = "static/#{query.match(/cmd=(\w+)/)[1]}.html"
        
        pages << { url: url, path: path }
      end
      
      pages
    end

    def discover_village_ids
      []  # 簡略版
    end

    def discover_user_ids
      []  # 簡略版
    end

    def process_pages(pages)
      progressbar = TTY::ProgressBar.new(
        "[:bar] :current/:total :percent",
        total: pages.size
      )
      
      pages.each { |page| @downloaded_paths.add(page[:path]) }
      
      pages.each_with_index do |page, index|
        begin
          process_single_page(page)
          @stats[:pages][:succeeded] += 1
        rescue => e
          puts "エラー: #{page[:url]} - #{e.message}"
          @stats[:pages][:failed] += 1
        ensure
          @stats[:pages][:total] += 1
          progressbar.advance
        end
      end
      
      progressbar.finish
    end

    def process_single_page(page)
      if @storage.exist?(page[:path])
        return
      end
      
      result = @fetcher.fetch(page[:url])
      
      unless result.success?
        raise "HTTP失敗: #{result.status}"
      end
      
      utf8_html = EncodingConverter.to_utf8(result.body, @site_config.encoding)
      parse_result = @parser.parse(utf8_html, page[:url])
      
      if @site_config.assets[:download] && parse_result.assets.any?
        download_result = @asset_downloader.download(parse_result.assets)
        
        @stats[:assets][:total] += download_result.total
        @stats[:assets][:succeeded] += download_result.succeeded.size
        @stats[:assets][:failed] += download_result.failed.size
        @stats[:assets][:skipped] += download_result.skipped.size
      end
      
      base_domain = URI.parse(@site_config.base_url).host
      rewriter = LinkRewriter.new(base_domain, @path_mapper, @downloaded_paths)
      rewritten_html = rewriter.rewrite(parse_result, page[:path])
      
      @storage.save(page[:path], rewritten_html)
    end

    def build_result
      ArchiveResult.new(
        total_pages: @stats[:pages][:total],
        succeeded_pages: @stats[:pages][:succeeded],
        failed_pages: @stats[:pages][:failed],
        total_assets: @stats[:assets][:total],
        succeeded_assets: @stats[:assets][:succeeded],
        failed_assets: @stats[:assets][:failed],
        skipped_assets: @stats[:assets][:skipped],
        start_time: @start_time,
        end_time: @end_time || Time.now
      )
    end
  end

  class ArchiveResult
    attr_reader :total_pages, :succeeded_pages, :failed_pages
    attr_reader :total_assets, :succeeded_assets, :failed_assets, :skipped_assets
    attr_reader :start_time, :end_time
    
    def initialize(total_pages:, succeeded_pages:, failed_pages:,
                   total_assets:, succeeded_assets:, failed_assets:, skipped_assets:,
                   start_time:, end_time:)
      @total_pages = total_pages
      @succeeded_pages = succeeded_pages
      @failed_pages = failed_pages
      @total_assets = total_assets
      @succeeded_assets = succeeded_assets
      @failed_assets = failed_assets
      @skipped_assets = skipped_assets
      @start_time = start_time
      @end_time = end_time
    end

    def duration
      @end_time - @start_time
    end

    def summary
      <<~SUMMARY
        アーカイブ完了
        
        ページ:
          合計: #{@total_pages}件
          成功: #{@succeeded_pages}件
          失敗: #{@failed_pages}件
        
        アセット:
          合計: #{@total_assets}件
          成功: #{@succeeded_assets}件
          失敗: #{@failed_assets}件
          スキップ: #{@skipped_assets}件
      SUMMARY
    end
  end
end
