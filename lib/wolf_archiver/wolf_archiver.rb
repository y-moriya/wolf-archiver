# WolfArchiver - メインクラス
# 詳細仕様: spec/wolf_archiver_spec.md を参照

require 'tty-progressbar'

module WolfArchiver
  class WolfArchiver
    def initialize(site_name:, config_path:, output_dir:)
      @logger = LoggerConfig.logger('WolfArchiver')
      @site_name = site_name
      @output_dir = output_dir

      @logger.info("WolfArchiver初期化開始: site=#{site_name}, output=#{output_dir}")

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
      @logger.info('WolfArchiver初期化完了')
    end

    def run(village_ids: nil, user_ids: nil, auto_discover: false,
            users_only: false, villages_only: false, static_only: false, force: false)
      @logger.info('=' * 60)
      @logger.info('アーカイブ処理開始')
      @logger.info("  - site: #{@site_name}")
      @logger.info("  - village_ids: #{village_ids}")
      @logger.info("  - user_ids: #{user_ids}")
      @logger.info("  - auto_discover: #{auto_discover}")
      @logger.info("  - users_only: #{users_only}")
      @logger.info("  - villages_only: #{villages_only}")
      @logger.info("  - static_only: #{static_only}")
      @logger.info("  - force: #{force}")
      @logger.info('=' * 60)

      pages = determine_pages(
        village_ids: village_ids,
        user_ids: user_ids,
        auto_discover: auto_discover,
        users_only: users_only,
        villages_only: villages_only,
        static_only: static_only
      )

      if pages.empty?
        @logger.warn('ダウンロード対象がありません')
        puts 'ダウンロード対象がありません'
        return build_result
      end

      @logger.info("ダウンロード対象: #{pages.size}ページ")
      puts "ダウンロード対象: #{pages.size}ページ"
      process_pages(pages, force: force)

      @end_time = Time.now
      result = build_result

      @logger.info('=' * 60)
      @logger.info(result.summary)
      @logger.info('=' * 60)
      puts '=' * 60
      puts result.summary
      puts '=' * 60

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

      if (query = @site_config.pages[:village_list])
        pages << { url: "#{@site_config.base_url}#{query}", path: 'village_list.html' }
      end

      village_ids.each do |village_id|
        # 村のindexページを追加
        if (query = @site_config.pages[:village_index])
          query = query.gsub('%{village_id}', village_id.to_s)
          url = "#{@site_config.base_url}#{query}"
          path = "villages/#{village_id}/index.html"
          pages << { url: url, path: path }
        end

        day_range = detect_day_range(village_id)
        min_day, max_day = day_range

        (min_day..max_day).each do |day|
          query = @site_config.pages[:village]
                              .gsub('%{village_id}', village_id.to_s)
                              .gsub('%{date}', day.to_s)

          url = "#{@site_config.base_url}#{query}"
          path = "villages/#{village_id}/day#{day}.html"

          pages << { url: url, path: path }

          # メモページを追加
          if (memo_query = @site_config.pages[:village_memo])
            memo_query = memo_query.gsub('%{village_id}', village_id.to_s)
                                   .gsub('%{date}', day.to_s)
            memo_url = "#{@site_config.base_url}#{memo_query}"
            memo_path = "villages/#{village_id}/day#{day}memo.html"
            pages << { url: memo_url, path: memo_path }
          end

          # 履歴ページを追加
          next unless (hist_query = @site_config.pages[:village_hist])

          hist_query = hist_query.gsub('%{village_id}', village_id.to_s)
                                 .gsub('%{date}', day.to_s)
          hist_url = "#{@site_config.base_url}#{hist_query}"
          hist_path = "villages/#{village_id}/day#{day}hist.html"
          pages << { url: hist_url, path: hist_path }
        end

        # vinfoページを追加
        next unless (query = @site_config.pages[:village_info])

        query = query.gsub('%{village_id}', village_id.to_s)
        url = "#{@site_config.base_url}#{query}"
        path = "villages/#{village_id}/vinfo.html"

        pages << { url: url, path: path }
      end

      pages
    end

    def detect_day_range(village_id)
      # まずday 0で取得を試みる
      query = @site_config.pages[:village]
                          .gsub('%{village_id}', village_id.to_s)
                          .gsub('%{date}', '0')

      url = "#{@site_config.base_url}#{query}"
      @logger.debug("day範囲検出: HTMLを取得中 - URL: #{url}")

      result = @fetcher.fetch(url)
      raise "村ページの取得に失敗: village_id=#{village_id}, status=#{result.status}" unless result.success?

      @logger.debug("day範囲検出: HTML取得成功 - village_id=#{village_id}")

      utf8_html = EncodingConverter.to_utf8(result.body, @site_config.encoding)
      doc = Nokogiri::HTML(utf8_html)

      # 日数選択のセレクトボックスから最小・最大日数を取得
      min_day = 0
      max_day = -Float::INFINITY

      # select_options_count = 0
      # doc.css('select[name="turn"] option').each do |option|
      #   day = option['value'].to_i
      #   min_day = day if day < min_day
      #   max_day = day if day > max_day
      #   select_options_count += 1
      # end

      # セレクトボックスが見つからない場合は、リンクから判定
      if max_day == -Float::INFINITY
        @logger.debug("day範囲検出: セレクトボックスが見つからないため、リンクから判定 - village_id=#{village_id}")

        link_count = 0
        doc.css('a').each do |link|
          next unless link['href'] =~ /turn=(\d+)/

          day = ::Regexp.last_match(1).to_i
          min_day = day if day < min_day
          max_day = day if day > max_day
          link_count += 1
        end

        @logger.debug("day範囲検出: リンクから #{link_count} 件の日数情報を検出 - village_id=#{village_id}")
      else
        @logger.debug("day範囲検出: セレクトボックスから #{select_options_count} 件のオプションを検出 - village_id=#{village_id}")
      end

      # 見つからない場合はエラー
      if min_day == Float::INFINITY || max_day == -Float::INFINITY
        raise "day範囲の検出に失敗: village_id=#{village_id} - HTMLから日数情報を取得できませんでした"
      end

      @logger.info("村 #{village_id} のday範囲を検出: #{min_day}～#{max_day}")
      @logger.debug("day範囲検出完了: village_id=#{village_id}, min_day=#{min_day}, max_day=#{max_day}, 検出元URL=#{url}")
      [min_day, max_day]
    rescue StandardError => e
      @logger.error("day範囲の検出に失敗: village_id=#{village_id}, error=#{e.message}")
      raise # エラーを再スロー
    end

    def build_user_pages(user_ids)
      pages = []

      if (query = @site_config.pages[:user_list])
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

    def process_pages(pages, force: false)
      @logger.info("ページ処理開始: #{pages.size}件")
      progressbar = TTY::ProgressBar.new(
        '[:bar] :current/:total :percent',
        total: pages.size
      )

      pages.each { |page| @downloaded_paths.add(page[:path]) }

      pages.each_with_index do |page, index|
        @logger.debug("ページ処理: #{page[:url]} => #{page[:path]}")
        process_single_page(page, force: force)
        @stats[:pages][:succeeded] += 1
      rescue StandardError => e
        @logger.error("ページ処理エラー: #{page[:url]} - #{e.message}")
        puts "エラー: #{page[:url]} - #{e.message}"
        @stats[:pages][:failed] += 1
      ensure
        @stats[:pages][:total] += 1
        progressbar.advance
      end

      progressbar.finish
      @logger.info("ページ処理完了: 成功=#{@stats[:pages][:succeeded]}, 失敗=#{@stats[:pages][:failed]}")
    end

    def process_single_page(page, force: false)
      if !force && @storage.exist?(page[:path])
        @logger.debug("ページスキップ(既存): #{page[:path]}")
        return
      end

      @logger.debug("ページ上書き: #{page[:path]}") if force && @storage.exist?(page[:path])

      result = @fetcher.fetch(page[:url])

      raise "HTTP失敗: #{result.status}" unless result.success?

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
    attr_reader :total_pages, :succeeded_pages, :failed_pages, :total_assets, :succeeded_assets, :failed_assets,
                :skipped_assets, :start_time, :end_time

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
