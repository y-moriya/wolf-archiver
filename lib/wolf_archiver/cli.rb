# CLI - コマンドラインインターフェース
# 詳細仕様: spec/wolf_archiver_spec.md を参照

require 'thor'

module WolfArchiver
  class WolfArchiverCLI < Thor
    def initialize(*args)
      super
      @logger = LoggerConfig.logger('CLI')
    end
    desc 'fetch SITE_NAME', 'サイトをアーカイブ'
    option :output, aliases: '-o', default: './archive', desc: '出力ディレクトリ'
    option :config, aliases: '-c', default: 'config/sites.yml', desc: '設定ファイル'
    option :village_ids, type: :array, desc: '取得する村IDリスト'
    option :user_ids, type: :array, desc: '取得するユーザーIDリスト'
    option :auto_discover, type: :boolean, default: false, desc: '自動検出'
    option :users_only, type: :boolean, default: false, desc: 'ユーザーのみ'
    option :villages_only, type: :boolean, default: false, desc: '村のみ'
    option :static_only, type: :boolean, default: false, desc: '静的ページのみ'
    def fetch(site_name)
      @logger.info("=" * 60)
      @logger.info("fetch コマンド実行開始")
      @logger.info("サイト名: #{site_name}")
      @logger.info("オプション:")
      @logger.info("  - output: #{options[:output]}")
      @logger.info("  - config: #{options[:config]}")
      @logger.info("  - village_ids: #{options[:village_ids]}")
      @logger.info("  - user_ids: #{options[:user_ids]}")
      @logger.info("  - auto_discover: #{options[:auto_discover]}")
      @logger.info("  - users_only: #{options[:users_only]}")
      @logger.info("  - villages_only: #{options[:villages_only]}")
      @logger.info("  - static_only: #{options[:static_only]}")
      @logger.info("=" * 60)
      
      archiver = WolfArchiver.new(
        site_name: site_name,
        config_path: options[:config],
        output_dir: options[:output]
      )
      
      archiver.run(
        village_ids: options[:village_ids],
        user_ids: options[:user_ids],
        auto_discover: options[:auto_discover],
        users_only: options[:users_only],
        villages_only: options[:villages_only],
        static_only: options[:static_only]
      )
      
      @logger.info("fetch コマンド実行完了")
    rescue => e
      @logger.error("fetch コマンド実行エラー: #{e.message}")
      @logger.error("バックトレース: #{e.backtrace.first(5).join("\n")}")
      error("エラー: #{e.message}")
      exit 1
    end

    desc 'version', 'バージョンを表示'
    def version
      @logger.info("version コマンド実行")
      puts "WolfArchiver #{VERSION}"
    end

    desc 'list', 'サイト一覧を表示'
    option :config, aliases: '-c', default: 'config/sites.yml', desc: '設定ファイル'
    def list
      @logger.info("list コマンド実行開始")
      @logger.info("設定ファイル: #{options[:config]}")
      
      loader = ConfigLoader.new(options[:config])
      
      puts "設定されているサイト:"
      loader.site_names.each do |name|
        site = loader.site(name)
        puts "  - #{name}: #{site.name}"
      end
      
      @logger.info("list コマンド実行完了（#{loader.site_names.size}件）")
    rescue => e
      @logger.error("list コマンド実行エラー: #{e.message}")
      error("エラー: #{e.message}")
      exit 1
    end
  end
end
