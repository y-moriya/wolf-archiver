# ConfigLoader - 設定ファイル読み込み
# 詳細仕様: spec/config_loader_spec.md を参照

require 'yaml'
require 'uri'

module WolfArchiver
  class ConfigLoader
    def initialize(config_path)
      @logger = LoggerConfig.logger('ConfigLoader')
      @config_path = config_path

      @logger.info("設定ファイル読み込み開始: #{config_path}")

      unless File.exist?(config_path)
        @logger.error("設定ファイルが見つかりません: #{config_path}")
        raise ConfigError, "設定ファイルが見つかりません: #{config_path}"
      end

      begin
        @config = YAML.load_file(config_path, permitted_classes: [Symbol])
        @logger.debug('YAMLパース成功')
      rescue Psych::SyntaxError, Psych::ParserError => e
        @logger.error("YAMLパースエラー: #{e.message}")
        raise ConfigError, "YAMLパースエラー: #{e.message}"
      rescue StandardError => e
        @logger.error("設定ファイル読み込み失敗: #{e.message}")
        raise ConfigError, "設定ファイル読み込み失敗: #{e.message}"
      end

      validate_config
      @logger.info('設定ファイル読み込み完了')
    end

    def site(site_name)
      @logger.debug("サイト設定取得: #{site_name}")
      sites = @config['sites'] || {}
      site_data = sites[site_name.to_s]

      if site_data.nil?
        available = sites.keys.join(', ')
        @logger.error("サイト '#{site_name}' が見つかりません。利用可能: #{available}")
        raise ConfigError, "サイト '#{site_name}' が見つかりません。利用可能: #{available}"
      end

      SiteConfig.new(site_name, site_data)
    end

    def site_names
      sites = @config['sites'] || {}
      sites.keys || []
    end

    private

    def validate_config
      @logger.debug('設定ファイル検証開始')
      # 仕様に従った検証処理
      # 現時点では簡略版
      unless @config.is_a?(Hash)
        @logger.error('設定ファイルがハッシュではありません')
        raise ConfigError, '設定ファイルは YAML ハッシュである必要があります'
      end

      unless @config['sites'].is_a?(Hash)
        @logger.error('sites キーが見つかりません')
        raise ConfigError, 'sites キーが見つかりません'
      end
      @logger.debug('設定ファイル検証完了')
    end
  end

  class SiteConfig
    attr_reader :name, :base_url, :encoding, :wait_time, :initial_day, :assets, :link_rewrite, :pages, :path_mapping

    def initialize(site_key, data)
      @site_key = site_key
      @name = data['name']
      @base_url = data['base_url']
      @encoding = data['encoding']
      @wait_time = data['wait_time']
      @initial_day = data['initial_day'] || 0

      # オプション項目（デフォルト値）
      @assets = merge_defaults(
        data['assets'] || {},
        {
          download: true,
          types: %w[css js images],
          css_dir: 'assets/css',
          js_dir: 'assets/js',
          images_dir: 'assets/images'
        }
      )

      @link_rewrite = merge_defaults(
        data['link_rewrite'] || {},
        {
          enabled: true,
          exclude_domains: [],
          fallback: '#'
        }
      )

      @pages = (data['pages'] || {}).transform_keys(&:to_sym)
      @path_mapping = data['path_mapping'] || []

      validate
    end

    def localhost?
      uri = URI.parse(@base_url)
      ['localhost', '127.0.0.1', '::1'].include?(uri.host)
    rescue URI::InvalidURIError
      false
    end

    def actual_wait_time
      localhost? ? 0 : @wait_time
    end

    private

    def merge_defaults(user_config, defaults)
      defaults.merge(user_config.transform_keys(&:to_sym))
    end

    def validate
      raise ConfigError, 'name が設定されていません' if @name.nil?
      raise ConfigError, 'base_url が設定されていません' if @base_url.nil?
      raise ConfigError, 'encoding が設定されていません' if @encoding.nil?
      raise ConfigError, 'wait_time が設定されていません' if @wait_time.nil?

      raise ConfigError, 'wait_time は0以上である必要があります' if @wait_time < 0
    end
  end
end
