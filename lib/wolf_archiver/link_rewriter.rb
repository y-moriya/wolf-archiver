# LinkRewriter - リンク書き換え
# 詳細仕様: spec/link_rewriter_spec.md を参照

module WolfArchiver
  class LinkRewriter
    def initialize(base_domain, path_mapper, downloaded_paths)
      @logger = LoggerConfig.logger('LinkRewriter')
      @base_domain = base_domain
      @path_mapper = path_mapper
      @downloaded_paths = downloaded_paths
      @relative_path_cache = {}
      @logger.info("LinkRewriter初期化: base_domain=#{base_domain}")
    end

    def rewrite(parse_result, current_file_path)
      @logger.debug("リンク書き換え開始: #{current_file_path}")
      doc = parse_result.document.dup
      
      rewrite_links(doc, parse_result.links, current_file_path)
      rewrite_assets(doc, parse_result.assets, current_file_path)
      
      @logger.debug("リンク書き換え完了: リンク=#{parse_result.links.size}件, アセット=#{parse_result.assets.size}件")
      doc.to_html
    rescue => e
      @logger.error("リンク書き換えエラー: #{e.message}")
      raise LinkRewriterError, "リンク書き換えエラー: #{e.message}"
    end

    def calculate_relative_path(from_path, to_path)
      cache_key = "#{from_path}::#{to_path}"
      @relative_path_cache[cache_key] ||= compute_relative_path(from_path, to_path)
    end

    private

    def rewrite_links(doc, links, current_file_path)
      links.each do |link|
        new_url = rewrite_page_link(link, current_file_path)
        # コピーしたドキュメントから対応する要素を見つける
        element = find_element_in_doc(doc, link.element)
        element[link.attribute] = new_url if element
      end
    end

    def rewrite_assets(doc, assets, current_file_path)
      assets.each do |asset|
        new_url = rewrite_asset(asset, current_file_path)
        # コピーしたドキュメントから対応する要素を見つける
        element = find_element_in_doc(doc, asset.element)
        element[asset.attribute] = new_url if element
      end
    end

    def find_element_in_doc(doc, original_element)
      # タグ名と属性値で要素を検索
      tag_name = original_element.name
      
      # 主要な属性（href, src）をチェック
      ['href', 'src'].each do |attr|
        value = original_element[attr]
        next unless value
        
        # 属性値で要素を検索（エスケープが必要な場合がある）
        escaped_value = value.gsub("'", "\\'")
        element = doc.at_css("#{tag_name}[#{attr}='#{escaped_value}']")
        return element if element
      end
      
      # 見つからない場合はnil
      nil
    end

    def rewrite_page_link(link, current_file_path)
      return link.url if link.external?(@base_domain)
      return link.url if link.anchor?
      
      target_path = @path_mapper.url_to_path(link.url)
      
      return '#' if target_path.nil?
      return '#' unless @downloaded_paths.include?(target_path)
      
      calculate_relative_path(current_file_path, target_path)
    end

    def rewrite_asset(asset, current_file_path)
      # 外部アセットはそのまま保持
      return asset.url if external_asset?(asset.url)
      
      target_path = @path_mapper.url_to_path(asset.url)
      
      return '#' if target_path.nil?
      
      calculate_relative_path(current_file_path, target_path)
    end

    def external_asset?(url)
      uri = Addressable::URI.parse(url)
      return false unless uri.host
      uri.host != @base_domain && !uri.host.end_with?(".#{@base_domain}")
    rescue
      false
    end

    def compute_relative_path(from_path, to_path)
      from_path = Pathname.new(from_path).cleanpath.to_s
      to_path = Pathname.new(to_path).cleanpath.to_s
      
      # 同じファイルの場合は"."を返す
      return '.' if from_path == to_path
      
      from_parts = from_path.split('/')
      to_parts = to_path.split('/')
      
      from_dir_parts = from_parts[0...-1]
      
      common_length = 0
      [from_dir_parts.length, to_parts.length].min.times do |i|
        break if from_dir_parts[i] != to_parts[i]
        common_length += 1
      end
      
      up_count = from_dir_parts.length - common_length
      up_parts = ['..'] * up_count
      down_parts = to_parts[common_length..-1]
      
      relative_parts = up_parts + down_parts
      relative_parts.empty? ? '.' : relative_parts.join('/')
    end
  end
end
