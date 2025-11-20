# Parser - HTML解析
# 詳細仕様: spec/parser_spec.md を参照

require 'nokogiri'
require 'addressable'

module WolfArchiver
  class Parser
    def initialize(base_url)
      @logger = LoggerConfig.logger('Parser')
      @base_url = base_url
      @logger.info("Parser初期化: base_url=#{base_url}")
    end

    def parse(html, current_url)
      @logger.debug("HTML解析開始: #{current_url}")
      doc = Nokogiri::HTML(html, nil, 'UTF-8')
      base = extract_base_url(doc, current_url)
      
      links = extract_links(doc, base)
      assets = extract_assets(doc, base)
      inline_assets = extract_inline_assets(doc, base)
      
      @logger.debug("HTML解析完了: リンク=#{links.size}件, アセット=#{assets.size}件, インラインアセット=#{inline_assets.size}件")
      
      ParseResult.new(
        document: doc,
        links: links,
        assets: assets,
        inline_assets: inline_assets
      )
    rescue => e
      @logger.error("HTML解析エラー: #{current_url} - #{e.message}")
      raise ParserError.new("HTML解析エラー: #{e.message}", url: current_url, original_error: e)
    end

    private

    def extract_base_url(doc, current_url)
      base_element = doc.at_css('base[href]')
      
      if base_element
        href = base_element['href']
        Addressable::URI.parse(current_url).join(href).to_s
      else
        current_url
      end
    end

    def extract_links(doc, base_url)
      links = []
      
      doc.css('a[href]').each do |element|
        href = element['href'].strip
        next if skip_link?(href)
        
        absolute_url = resolve_url(href, base_url)
        next unless absolute_url
        
        links << Link.new(
          url: absolute_url,
          element: element,
          attribute: 'href',
          text: element.text.strip
        )
      end
      
      links
    end

    def extract_assets(doc, base_url)
      assets = []
      
      # CSS
      doc.css('link[rel="stylesheet"][href]').each do |element|
        href = element['href'].strip
        next if href.empty?
        
        absolute_url = resolve_url(href, base_url)
        next unless absolute_url
        
        assets << Asset.new(
          url: absolute_url,
          type: :css,
          element: element,
          attribute: 'href'
        )
      end
      
      # JavaScript
      doc.css('script[src]').each do |element|
        src = element['src'].strip
        next if src.empty?
        
        absolute_url = resolve_url(src, base_url)
        next unless absolute_url
        
        assets << Asset.new(
          url: absolute_url,
          type: :js,
          element: element,
          attribute: 'src'
        )
      end
      
      # 画像
      doc.css('img[src]').each do |element|
        src = element['src'].strip
        next if src.empty? || src.start_with?('data:')
        
        absolute_url = resolve_url(src, base_url)
        next unless absolute_url
        
        assets << Asset.new(
          url: absolute_url,
          type: :image,
          element: element,
          attribute: 'src'
        )
      end
      
      assets
    end

    def extract_inline_assets(doc, base_url)
      inline_assets = []
      
      # style タグ
      doc.css('style').each do |element|
        content = element.content
        urls = extract_urls_from_css(content, base_url)
        
        if urls.any?
          inline_assets << InlineAsset.new(
            urls: urls,
            type: :inline_css,
            element: element,
            content: content
          )
        end
      end
      
      inline_assets
    end

    def extract_urls_from_css(css_content, base_url)
      urls = []
      
      css_content.scan(/url\s*\(\s*(['"]?)(.+?)\1\s*\)/i) do |_, url|
        url = url.strip
        next if url.empty? || url.start_with?('data:')
        
        absolute_url = resolve_url(url, base_url)
        urls << absolute_url if absolute_url
      end
      
      urls.uniq
    end

    def resolve_url(url, base_url)
      return nil if url.nil? || url.empty?
      
      return remove_fragment(url) if url.start_with?('http://', 'https://')
      
      if url.start_with?('//')
        base_uri = Addressable::URI.parse(base_url)
        return remove_fragment("#{base_uri.scheme}:#{url}")
      end
      
      base_uri = Addressable::URI.parse(base_url)
      resolved_uri = base_uri.join(url)
      resolved_uri.fragment = nil
      resolved_uri.to_s
    rescue Addressable::URI::InvalidURIError
      nil
    end

    def remove_fragment(url)
      uri = Addressable::URI.parse(url)
      uri.fragment = nil
      uri.to_s
    rescue
      url
    end

    def skip_link?(href)
      href.empty? ||
      href.start_with?('#') ||
      href.start_with?('javascript:') ||
      href.start_with?('mailto:') ||
      href.start_with?('tel:') ||
      href.start_with?('data:')
    end
  end

  class ParseResult
    attr_reader :document, :links, :assets, :inline_assets
    
    def initialize(document:, links:, assets:, inline_assets:)
      @document = document
      @links = links
      @assets = assets
      @inline_assets = inline_assets
    end

    def all_urls
      (links.map(&:url) + assets.map(&:url) + inline_assets.flat_map(&:urls)).uniq
    end
  end

  class Link
    attr_reader :url, :element, :attribute, :text
    
    def initialize(url:, element:, attribute:, text: nil)
      @url = url
      @element = element
      @attribute = attribute
      @text = text
    end

    def internal?(base_domain)
      uri = Addressable::URI.parse(@url)
      return false unless uri.host
      uri.host == base_domain || uri.host.end_with?(".#{base_domain}")
    rescue
      false
    end

    def external?(base_domain)
      !internal?(base_domain)
    end

    def anchor?
      @url.start_with?('#')
    end
  end

  class Asset
    attr_reader :url, :type, :element, :attribute
    
    def initialize(url:, type:, element:, attribute:)
      @url = url
      @type = type
      @element = element
      @attribute = attribute
    end

    def extension
      case @type
      when :css
        '.css'
      when :js
        '.js'
      when :image
        ext = File.extname(URI.parse(@url).path).downcase
        ext.empty? ? '.png' : ext
      else
        ''
      end
    end
  end

  class InlineAsset
    attr_reader :urls, :type, :element, :content
    
    def initialize(urls:, type:, element:, content:)
      @urls = urls
      @type = type
      @element = element
      @content = content
    end
  end

  class ParserError < WolfArchiverError
    attr_reader :url, :original_error

    def initialize(message, url: nil, original_error: nil)
      @url = url
      @original_error = original_error
      super(message)
    end
  end
end
