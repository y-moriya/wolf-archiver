# ConfigLoader - 設定ファイル読み込み
# 詳細仕様: spec/config_loader_spec.md を参照

require 'yaml'
require 'uri'

module WolfArchiver
  class ConfigLoader
    def initialize(config_path)
      @config_path = config_path
      
      unless File.exist?(config_path)
        raise ConfigError, "設定ファイルが見つかりません: #{config_path}"
      end
      
      begin
        @config = YAML.load_file(config_path, permitted_classes: [Symbol])
      rescue YAML::ParserError => e
        raise ConfigError, "YAMLパースエラー: #{e.message}"
      rescue => e
        raise ConfigError, "設定ファイル読み込み失敗: #{e.message}"
      end
      
      validate_config
    end

    def site(site_name)
      site_data = @config.dig('sites', site_name.to_s)
      
      if site_data.nil?
        available = @config.dig('sites', {}).keys.join(', ')
        raise ConfigError, "サイト '#{site_name}' が見つかりません。利用可能: #{available}"
      end
      
      SiteConfig.new(site_name, site_data)
    end

    def site_names
      @config.dig('sites', {}).keys || []
    end

    private

    def validate_config
      # 仕様に従った検証処理
      # 現時点では簡略版
      unless @config.is_a?(Hash)
        raise ConfigError, "設定ファイルは YAML ハッシュである必要があります"
      end
      
      unless @config['sites'].is_a?(Hash)
        raise ConfigError, "sites キーが見つかりません"
      end
    end
  end

  class SiteConfig
    attr_reader :name, :base_url, :encoding, :wait_time
    attr_reader :assets, :link_rewrite, :pages, :path_mapping

    def initialize(site_key, data)
      @site_key = site_key
      @name = data['name']
      @base_url = data['base_url']
      @encoding = data['encoding']
      @wait_time = data['wait_time']
      
      # オプション項目（デフォルト値）
      @assets = merge_defaults(
        data['assets'] || {},
        {
          download: true,
          types: ['css', 'js', 'images'],
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
      
      @pages = data['pages'] || {}
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
      raise ConfigError, "name が設定されていません" if @name.nil?
      raise ConfigError, "base_url が設定されていません" if @base_url.nil?
      raise ConfigError, "encoding が設定されていません" if @encoding.nil?
      raise ConfigError, "wait_time が設定されていません" if @wait_time.nil?
      
      raise ConfigError, "wait_time は0以上である必要があります" if @wait_time < 0
    end
  end
end
