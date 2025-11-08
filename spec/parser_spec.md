# Parser 詳細仕様

## 1. 責務

HTMLを解析し、ページ内のリンクとアセット（CSS/JS/画像）を抽出する。
相対URLを絶対URLに変換し、後続処理（ダウンロード、リンク書き換え）に必要な情報を提供する。

## 2. インターフェース

### 2.1 クラス定義

```ruby
class Parser
  # 初期化
  # @param base_url [String] ベースURL（相対URL解決用）
  def initialize(base_url)
  
  # HTMLを解析してリンクとアセットを抽出
  # @param html [String] HTML文字列（UTF-8）
  # @param current_url [String] 現在のページのURL
  # @return [ParseResult] 解析結果
  # @raise [ParserError] 解析失敗時
  def parse(html, current_url)
end

class ParseResult
  attr_reader :document, :links, :assets, :inline_assets
  
  # @param document [Nokogiri::HTML::Document] パース済みドキュメント
  # @param links [Array<Link>] ページリンクのリスト
  # @param assets [Array<Asset>] アセットのリスト
  # @param inline_assets [Array<InlineAsset>] インラインアセットのリスト
  def initialize(document:, links:, assets:, inline_assets:)
  
  # すべてのURL（リンク+アセット）
  # @return [Array<String>]
  def all_urls
end

class Link
  attr_reader :url, :element, :attribute, :text
  
  # @param url [String] 絶対URL
  # @param element [Nokogiri::XML::Element] リンク要素
  # @param attribute [String] URL属性名（'href', 'src'など）
  # @param text [String, nil] リンクテキスト
  def initialize(url:, element:, attribute:, text: nil)
  
  # 内部リンクか（同一ドメイン）
  # @param base_domain [String] ベースドメイン
  # @return [Boolean]
  def internal?(base_domain)
  
  # アンカーリンクか（#で始まる）
  # @return [Boolean]
  def anchor?
end

class Asset
  attr_reader :url, :type, :element, :attribute
  
  # @param url [String] 絶対URL
  # @param type [Symbol] アセットタイプ (:css, :js, :image)
  # @param element [Nokogiri::XML::Element] アセット要素
  # @param attribute [String] URL属性名
  def initialize(url:, type:, element:, attribute:)
  
  # ファイル拡張子を推測
  # @return [String] 拡張子（例: '.css', '.js', '.png'）
  def extension
end

class InlineAsset
  attr_reader :urls, :type, :element, :content
  
  # @param urls [Array<String>] URL配列
  # @param type [Symbol] タイプ (:inline_css, :inline_js)
  # @param element [Nokogiri::XML::Element] 要素
  # @param content [String] 元のコンテンツ
  def initialize(urls:, type:, element:, content:)
end

class ParserError < StandardError
  attr_reader :url, :original_error
  
  def initialize(message, url: nil, original_error: nil)
    @url = url
    @original_error = original_error
    super(message)
  end
end
```

## 3. 解析対象

### 3.1 ページリンク

| 要素 | 属性 | 例 |
|------|------|-----|
| `<a>` | `href` | `<a href="page.html">リンク</a>` |
| `<area>` | `href` | `<area href="map.html">` |
| `<form>` | `action` | `<form action="submit.cgi">` |

**除外**: 
- `href="#"` （アンカーリンク）
- `href="javascript:..."` （JavaScriptスキーム）
- `href="mailto:..."` （メールスキーム）
- `href="tel:..."` （電話スキーム）

### 3.2 CSS

| 要素 | 属性 | 例 |
|------|------|-----|
| `<link rel="stylesheet">` | `href` | `<link rel="stylesheet" href="style.css">` |
| `<style>` | (内容) | `<style>body { background: url(...) }</style>` |
| 要素の `style` 属性 | `style` | `<div style="background: url(...)">` |

### 3.3 JavaScript

| 要素 | 属性 | 例 |
|------|------|-----|
| `<script>` | `src` | `<script src="app.js"></script>` |

### 3.4 画像

| 要素 | 属性 | 例 |
|------|------|-----|
| `<img>` | `src` | `<img src="image.png">` |
| `<img>` | `srcset` | `<img srcset="img1.png 1x, img2.png 2x">` |
| `<source>` | `src` | `<source src="video.mp4">` |
| `<source>` | `srcset` | `<source srcset="img.png">` |
| `<video>` | `poster` | `<video poster="thumb.jpg">` |
| `<input type="image">` | `src` | `<input type="image" src="btn.png">` |

## 4. URL抽出処理

### 4.1 基本的な解析フロー

```ruby
def parse(html, current_url)
  # 1. HTMLをパース
  doc = Nokogiri::HTML(html)
  
  # 2. ベースURLを取得（<base>タグがあれば優先）
  base = extract_base_url(doc, current_url)
  
  # 3. ページリンクを抽出
  links = extract_links(doc, base)
  
  # 4. アセットを抽出
  assets = extract_assets(doc, base)
  
  # 5. インラインアセットを抽出
  inline_assets = extract_inline_assets(doc, base)
  
  ParseResult.new(
    document: doc,
    links: links,
    assets: assets,
    inline_assets: inline_assets
  )
rescue => e
  raise ParserError.new("HTML解析エラー: #{e.message}", url: current_url, original_error: e)
end
```

### 4.2 ベースURL取得

```ruby
def extract_base_url(doc, current_url)
  # <base href="...">タグを確認
  base_element = doc.at_css('base[href]')
  
  if base_element
    href = base_element['href']
    Addressable::URI.parse(current_url).join(href).to_s
  else
    current_url
  end
end
```

### 4.3 リンク抽出

```ruby
def extract_links(doc, base_url)
  links = []
  
  # <a href="...">
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
  
  # <area href="...">
  doc.css('area[href]').each do |element|
    href = element['href'].strip
    next if skip_link?(href)
    
    absolute_url = resolve_url(href, base_url)
    next unless absolute_url
    
    links << Link.new(
      url: absolute_url,
      element: element,
      attribute: 'href'
    )
  end
  
  links
end

def skip_link?(href)
  # アンカー、JavaScriptスキームなどをスキップ
  href.empty? ||
  href.start_with?('#') ||
  href.start_with?('javascript:') ||
  href.start_with?('mailto:') ||
  href.start_with?('tel:') ||
  href.start_with?('data:')
end
```

### 4.4 CSS抽出

```ruby
def extract_css(doc, base_url)
  assets = []
  
  # <link rel="stylesheet" href="...">
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
  
  assets
end
```

### 4.5 JavaScript抽出

```ruby
def extract_js(doc, base_url)
  assets = []
  
  # <script src="...">
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
  
  assets
end
```

### 4.6 画像抽出

```ruby
def extract_images(doc, base_url)
  assets = []
  
  # <img src="...">
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
  
  # <img srcset="...">（複数URL）
  doc.css('img[srcset]').each do |element|
    srcset = element['srcset'].strip
    urls = parse_srcset(srcset, base_url)
    
    urls.each do |url|
      assets << Asset.new(
        url: url,
        type: :image,
        element: element,
        attribute: 'srcset'
      )
    end
  end
  
  # その他の画像要素
  # <input type="image" src="...">
  doc.css('input[type="image"][src]').each do |element|
    src = element['src'].strip
    next if src.empty?
    
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
```

### 4.7 インラインCSS/JSからのURL抽出

```ruby
def extract_inline_assets(doc, base_url)
  inline_assets = []
  
  # <style>...</style>
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
  
  # style属性
  doc.css('[style]').each do |element|
    content = element['style']
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
  
  # url(...)パターンを抽出
  # 例: background: url('image.png')
  #     background: url("image.png")
  #     background: url(image.png)
  css_content.scan(/url\s*\(\s*(['"]?)(.+?)\1\s*\)/i) do |_, url|
    url = url.strip
    next if url.empty? || url.start_with?('data:')
    
    absolute_url = resolve_url(url, base_url)
    urls << absolute_url if absolute_url
  end
  
  urls.uniq
end
```

### 4.8 srcset属性のパース

```ruby
def parse_srcset(srcset, base_url)
  # srcset形式: "image1.png 1x, image2.png 2x, image3.png 480w"
  urls = []
  
  srcset.split(',').each do |entry|
    # URLと記述子（1x, 2x, 480wなど）を分離
    parts = entry.strip.split(/\s+/)
    url = parts.first
    next if url.nil? || url.empty?
    
    absolute_url = resolve_url(url, base_url)
    urls << absolute_url if absolute_url
  end
  
  urls
end
```

## 5. URL解決

### 5.1 相対URL → 絶対URL変換

```ruby
def resolve_url(url, base_url)
  return nil if url.nil? || url.empty?
  
  # 既に絶対URLの場合
  return remove_fragment(url) if url.start_with?('http://', 'https://')
  
  # プロトコル相対URL（//example.com/...）
  if url.start_with?('//')
    base_uri = Addressable::URI.parse(base_url)
    return remove_fragment("#{base_uri.scheme}:#{url}")
  end
  
  # 相対URLを解決
  base_uri = Addressable::URI.parse(base_url)
  resolved_uri = base_uri.join(url)
  
  # フラグメント（#...）を除去
  resolved_uri.fragment = nil
  
  resolved_uri.to_s
rescue Addressable::URI::InvalidURIError => e
  logger.warn("Parser: URL解決失敗 #{url} - #{e.message}")
  nil
end
```

### 5.2 フラグメントの除去

```ruby
def remove_fragment(url)
  uri = Addressable::URI.parse(url)
  
  # フラグメント（#anchor）を除去
  # 理由：同じページの異なるアンカーは同一ファイルとして扱う
  uri.fragment = nil
  
  uri.to_s
rescue => e
  logger.warn("Parser: URL処理失敗 #{url} - #{e.message}")
  url
end
```

## 6. 内部/外部リンクの判定

### 6.1 ドメイン比較

```ruby
class Link
  def internal?(base_domain)
    uri = Addressable::URI.parse(@url)
    return false unless uri.host
    
    # 同一ドメインまたはサブドメイン
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
```

### 6.2 使用例

```ruby
base_domain = 'example.com'

link = Link.new(url: 'http://example.com/page1', ...)
link.internal?(base_domain)  # => true

link = Link.new(url: 'http://sub.example.com/page1', ...)
link.internal?(base_domain)  # => true

link = Link.new(url: 'http://other.com/page1', ...)
link.internal?(base_domain)  # => false
```

## 7. エラーハンドリング

### 7.1 不正なHTML

```ruby
# Nokogiriは不正なHTMLも寛容にパース
doc = Nokogiri::HTML(html)

# 完全にパース不可の場合のみエラー
if doc.nil? || doc.errors.any? { |e| e.fatal? }
  raise ParserError.new("HTMLパース失敗")
end
```

### 7.2 不正なURL

```ruby
def resolve_url(url, base_url)
  # ...
rescue Addressable::URI::InvalidURIError => e
  logger.warn("Parser: URL解決失敗 #{url} - #{e.message}")
  nil  # nilを返してスキップ
end
```

### 7.3 循環参照

抽出段階では循環参照を検出しない（ダウンロード制御側で管理）。

## 8. ログ出力

### 8.1 ログレベル

| レベル | 内容 |
|--------|------|
| DEBUG | 抽出したリンク数、アセット数 |
| INFO | 解析完了 |
| WARN | URL解決失敗 |
| ERROR | 解析失敗 |

### 8.2 ログメッセージ例

```ruby
# DEBUG
"Parser: リンク抽出 25件"
"Parser: アセット抽出 CSS:3, JS:2, 画像:15"
"Parser: インラインCSS URL抽出 8件"

# INFO
"Parser: 解析完了 http://example.com/page1 (45件のURL)"

# WARN
"Parser: URL解決失敗 invalid-url - Invalid URI"

# ERROR
"Parser: HTML解析エラー - Invalid byte sequence"
```

## 9. 使用例

### 9.1 基本的な使用

```ruby
parser = Parser.new('http://example.com')

html = fetcher.fetch('?cmd=top').body
result = parser.parse(html, 'http://example.com?cmd=top')

# リンク一覧
result.links.each do |link|
  puts "#{link.url} (#{link.text})"
end

# アセット一覧
result.assets.each do |asset|
  puts "#{asset.type}: #{asset.url}"
end

# インラインアセット
result.inline_assets.each do |inline|
  puts "Inline #{inline.type}: #{inline.urls.join(', ')}"
end

# すべてのURL
result.all_urls.each do |url|
  puts url
end
```

### 9.2 内部リンクのフィルタリング

```ruby
base_domain = URI.parse(parser.base_url).host

internal_links = result.links.select { |link| link.internal?(base_domain) }
external_links = result.links.select { |link| link.external?(base_domain) }

puts "内部リンク: #{internal_links.size}件"
puts "外部リンク: #{external_links.size}件"
```

### 9.3 タイプ別アセット

```ruby
css_assets = result.assets.select { |a| a.type == :css }
js_assets = result.assets.select { |a| a.type == :js }
image_assets = result.assets.select { |a| a.type == :image }

puts "CSS: #{css_assets.size}件"
puts "JS: #{js_assets.size}件"
puts "画像: #{image_assets.size}件"
```

## 10. パフォーマンス考慮

### 10.1 CSS選択子の効率

```ruby
# 効率的
doc.css('a[href]')  # 属性セレクタを使用

# 非効率
doc.css('a').select { |a| a['href'] }  # 後処理でフィルタ
```

### 10.2 正規表現の最適化

```ruby
# CSS内のURL抽出
# 貪欲マッチを避ける: .+? （非貪欲）
css_content.scan(/url\s*\(\s*(['"]?)(.+?)\1\s*\)/i)
```

### 10.3 重複除去

```ruby
def all_urls
  (links.map(&:url) + assets.map(&:url) + inline_assets.flat_map(&:urls)).uniq
end
```

## 11. テストケース

### 11.1 正常系

- [ ] 基本的なHTMLのパース
- [ ] 相対URLの絶対URL変換
- [ ] `<a>`, `<img>`, `<link>`, `<script>`の抽出
- [ ] インラインCSSからのURL抽出
- [ ] style属性からのURL抽出
- [ ] srcset属性のパース
- [ ] `<base>`タグの処理
- [ ] 内部/外部リンクの判定
- [ ] プロトコル相対URL（//example.com）

### 11.2 異常系

- [ ] 不正なHTML → 寛容にパース
- [ ] 不正なURL → スキップ
- [ ] 空のHTML → 空の結果
- [ ] Data URI → スキップ
- [ ] JavaScriptスキーム → スキップ

### 11.3 エッジケース

- [ ] URLにクエリパラメータ、フラグメント
- [ ] 日本語を含むURL（パーセントエンコーディング）
- [ ] 相対パスの複雑な解決（../../など）
- [ ] srcsetに複数の画像
- [ ] CSSコメント内のURL（無視）
- [ ] 壊れたHTML（閉じタグなし）

## 12. 依存関係

- `nokogiri` gem
- `addressable` gem

## 13. 実装の注意点

### 13.1 Nokogiriのエンコーディング

```ruby
# UTF-8として扱う
doc = Nokogiri::HTML(html, nil, 'UTF-8')
```

### 13.2 要素の保持

LinkやAssetは元のNokogiri要素を保持するため、後でリンク書き換え時に使用できる：

```ruby
link.element['href'] = new_url
```

### 13.3 メモリ効率

大量のリンクがある場合、すべてをメモリに保持すると負荷が高い。
必要に応じてイテレータパターンを検討：

```ruby
# 現状（配列で返す）
def extract_links(doc, base_url)
  links = []
  doc.css('a[href]').each { |e| links << ... }
  links
end

# 代替案（イテレータ）：現時点では不要
def each_link(doc, base_url)
  doc.css('a[href]').each do |element|
    yield Link.new(...)
  end
end
```

## 14. 今後の拡張可能性

- メタタグの抽出（description, keywordsなど）
- RSSフィードの検出
- Open Graphタグの抽出
- ページタイトル、見出しの抽出
- 構造化データ（JSON-LD）の抽出
- CSSファイル内の@importの処理
- JavaScriptの動的URL生成への対応（限定的）

## 15. 次のステップ

Parserの仕様が確定したら、次は **LinkRewriter** に進みます。
LinkRewriterはParserで抽出したリンクとアセットを書き換える処理を担当します。
