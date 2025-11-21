# PathMapper - URLからファイルパスへのマッピング
# 詳細仕様: spec/link_rewriter_spec.md を参照

module WolfArchiver
  class PathMapper
    def initialize(base_url, path_mapping, assets_config)
      @logger = LoggerConfig.logger('PathMapper')
      @base_url = base_url
      @path_mapping = path_mapping.map do |m|
        mapping = { path_template: m['path'] }

        # パラメータベースのマッピング（新形式）
        if m['params']
          mapping[:params] = m['params'].transform_keys(&:to_sym)
          mapping[:exact] = m['exact'] || false # exactフラグ: 指定したパラメータのみを含む場合にマッチ
        # 正規表現ベースのマッピング（旧形式）
        elsif m['pattern']
          mapping[:pattern] = Regexp.new(m['pattern'])
        end

        mapping
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

      # クエリパラメータをパース
      query_params = parse_query_params(uri.query)

      # 各マッピングルールに対してマッチングを試行
      @path_mapping.each do |mapping|
        # パラメータベースのマッピング（新形式）
        if mapping[:params]
          result = match_params(query_params, mapping)
          if result
            @logger.debug("URL→パス変換(パラメータ): #{url} => #{result}")
            return result
          end
        # 正規表現ベースのマッピング（旧形式・後方互換性維持）
        elsif mapping[:pattern]
          query = uri.query || ''
          full_path = "#{uri.path}?#{query}".sub(/^\?/, '')

          if (match = mapping[:pattern].match(full_path))
            path = mapping[:path_template].dup
            match.captures.each_with_index do |capture, index|
              path.gsub!("%{#{index + 1}}", capture.to_s)
            end
            @logger.debug("URL→パス変換(正規表現): #{url} => #{path}")
            return path
          end
        end
      end

      @logger.debug("URL→パス変換失敗: #{url}")
      nil
    end

    private

    def parse_query_params(query_string)
      return {} if query_string.nil? || query_string.empty?

      params = {}
      query_string.split('&').each do |pair|
        key, value = pair.split('=', 2)
        params[key] = value || ''
      end
      params
    end

    def match_params(query_params, mapping)
      required_params = mapping[:params]
      exact_match = mapping[:exact]
      captures = {}

      # exactフラグがtrueの場合、パラメータ数が一致するかチェック
      return nil if exact_match && query_params.size != required_params.size

      # すべての必須パラメータが存在し、パターンにマッチするかチェック
      required_params.each do |param_name, pattern|
        param_value = query_params[param_name.to_s]

        # パラメータが存在しない場合はマッチ失敗
        return nil unless param_value

        # パターンが正規表現の場合はマッチングを行う
        if pattern.is_a?(String) && pattern.start_with?('(')
          regex = Regexp.new("^#{pattern}$")
          match = regex.match(param_value)
          return nil unless match

          # キャプチャグループがある場合は値を保存
          captures[param_name.to_s] = if match.captures.any?
                                        match.captures.first
                                      else
                                        param_value
                                      end
        else
          # 固定値の場合は完全一致をチェック
          return nil unless param_value == pattern

          captures[param_name.to_s] = param_value
        end
      end

      # パステンプレートを展開
      path = mapping[:path_template].dup
      captures.each do |key, value|
        path.gsub!("%{#{key}}", value.to_s)
      end

      path
    end

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
      base_uri = URI.parse(@base_url)

      # ベースURLのディレクトリ部分を取得（例: /sow/sow.cgi → /sow）
      base_dir = File.dirname(base_uri.path)

      # ベースディレクトリを除去して相対パスを取得
      # 例: /sow/img/icon.png → img/icon.png
      relative_path = uri.path.sub(%r{^#{Regexp.escape(base_dir)}/}, '')

      # 念のため先頭のスラッシュを除去
      relative_path.sub(%r{^/}, '')
    end
  end
end
