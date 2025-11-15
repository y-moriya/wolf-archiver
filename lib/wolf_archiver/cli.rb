# CLI - コマンドラインインターフェース
# 詳細仕様: spec/wolf_archiver_spec.md を参照

require 'thor'

module WolfArchiver
  class WolfArchiverCLI < Thor
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
    rescue => e
      error("エラー: #{e.message}")
      exit 1
    end

    desc 'version', 'バージョンを表示'
    def version
      puts "WolfArchiver #{VERSION}"
    end

    desc 'list', 'サイト一覧を表示'
    option :config, aliases: '-c', default: 'config/sites.yml', desc: '設定ファイル'
    def list
      loader = ConfigLoader.new(options[:config])
      
      puts "設定されているサイト:"
      loader.site_names.each do |name|
        site = loader.site(name)
        puts "  - #{name}: #{site.name}"
      end
    rescue => e
      error("エラー: #{e.message}")
      exit 1
    end
  end
end
