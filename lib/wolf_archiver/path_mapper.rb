# PathMapper - URLからファイルパスへのマッピング
# 詳細仕様: spec/link_rewriter_spec.md を参照

module WolfArchiver
  class PathMapper
    def initialize(base_url, path_mapping, assets_config)
      @logger = LoggerConfig.logger('PathMapper')
      @base_url = base_url
      @path_mapping = path_mapping.map do |m|
        {
          pattern: Regexp.new(m['pattern']),
          path_template: m['path']
        }
      end
      @assets_config = assets_config
      @logger.info("PathMapper初期化: マッピングルール=#{@path_mapping.size}件")
    end

    def url_to_path(url)
      uri = URI.parse(url)
      
      return nil unless same_host?(uri)
      
      if asset_url?(url)
        path = map_asset_path(url)
        @logger.debug("URL→パス変換(アセット): #{url} => #{path}")
        return path
      end
      
      query = uri.query || ''
      full_path = "#{uri.path}?#{query}".sub(/^\?/, '')
      
      @path_mapping.each do |mapping|
        if match = mapping[:pattern].match(full_path)
          path = mapping[:path_template].dup
          match.captures.each_with_index do |capture, index|
            path.gsub!("%{#{index + 1}}", capture.to_s)
          end
          @logger.debug("URL→パス変換(マッピング): #{url} => #{path}")
          return path
        end
      end
      
      @logger.debug("URL→パス変換失敗: #{url}")
      nil
    end

    private

    def same_host?(uri)
      base_uri = URI.parse(@base_url)
      uri.host == base_uri.host
    end

    def asset_url?(url)
      ext = File.extname(URI.parse(url).path).downcase
      ['.css', '.js', '.png', '.jpg', '.jpeg', '.gif', '.svg', '.webp'].include?(ext)
    end

    def map_asset_path(url)
      uri = URI.parse(url)
      filename = File.basename(uri.path)
      ext = File.extname(filename).downcase
      
      dir = case ext
            when '.css'
              @assets_config[:css_dir]
            when '.js'
              @assets_config[:js_dir]
            else
              @assets_config[:images_dir]
            end
      
      File.join(dir, filename)
    end
  end
end
