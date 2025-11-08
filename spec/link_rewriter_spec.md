# LinkRewriter 詳細仕様

## 1. 責務

HTML内のリンクとアセットのURLを、アーカイブ後のファイルパスに基づいた相対パスに書き換える。
書き換え不可のリンクは`#`に置換し、外部リンクはそのまま保持する。

## 2. インターフェース

### 2.1 クラス定義

```ruby
class LinkRewriter
  # 初期化
  # @param base_domain [String] ベースドメイン（内部/外部判定用）
  # @param path_mapper [PathMapper] URLからファイルパスへのマッピング
  # @param downloaded_paths [Set<String>] ダウンロード済みファイルパスの集合
  def initialize(base_domain, path_mapper, downloaded_paths)
  
  # HTMLのリンクを書き換え
  # @param parse_result [ParseResult] Parser の解析結果
  # @param current_file_path [String] 現在のHTMLファイルの相対パス（例: 'villages/1/day1.html'）
  # @return [String] 書き換え済みHTML
  # @raise [LinkRewriterError] 書き換え失敗時
  def rewrite(parse_result, current_file_path)
  
  # 相対パスを計算
  # @param from_path [String] 元のファイルパス
  # @param to_path [String] 先のファイルパス
  # @return [String] 相対パス
  def calculate_relative_path(from_path, to_path)
end

class PathMapper
  # URLをファイルパスにマッピング
  # @param url [String] 絶対URL
  # @return [String, nil] ファイルパス（マッピングできない場合はnil）
  def url_to_path(url)
end

class LinkRewriterError < StandardError
  attr_reader :current_path, :original_error
  
  def initialize(message, current_path: nil, original_error: nil)
    @current_path = current_path
    @original_error = original_error
    super(message)
  end
end
```

## 3. 相対パス計算

### 3.1 基本アルゴリズム

```ruby
def calculate_relative_path(from_path, to_path)
  # 1. パスを正規化
  from_path = Pathname.new(from_path).cleanpath.to_s
  to_path = Pathname.new(to_path).cleanpath.to_s
  
  # 2. 共通の祖先を見つける
  from_parts = from_path.split('/')
  to_parts = to_path.split('/')
  
  # ファイル名を除外（ディレクトリ部分のみ比較）
  from_dir_parts = from_parts[0...-1]
  
  # 3. 共通部分を特定
  common_length = 0
  [from_dir_parts.length, to_parts.length].min.times do |i|
    break if from_dir_parts[i] != to_parts[i]
    common_length += 1
  end
  
  # 4. 上の階層に戻る数を計算
  up_count = from_dir_parts.length - common_length
  
  # 5. 相対パスを構築
  up_parts = ['..'] * up_count
  down_parts = to_parts[common_length..-1]
  
  relative_parts = up_parts + down_parts
  relative_parts.empty? ? '.' : relative_parts.join('/')
end
```

### 3.2 計算例

```ruby
# 例1: 同じディレクトリ
calculate_relative_path('index.html', 'about.html')
# => 'about.html'

# 例2: 下の階層へ
calculate_relative_path('index.html', 'assets/css/style.css')
# => 'assets/css/style.css'

# 例3: 上の階層へ
calculate_relative_path('villages/1/day1.html', 'index.html')
# => '../../index.html'

# 例4: 異なる階層
calculate_relative_path('villages/1/day1.html', 'assets/css/style.css')
# => '../../assets/css/style.css'

# 例5: 深い階層
calculate_relative_path('villages/1/day1.html', 'villages/2/day3.html')
# => '../2/day3.html'
```

## 4. リンク書き換え処理

### 4.1 書き換えフロー

```ruby
def rewrite(parse_result, current_file_path)
  doc = parse_result.document.dup
  
  # 1. ページリンクを書き換え
  rewrite_links(doc, parse_result.links, current_file_path)
  
  # 2. アセットを書き換え
  rewrite_assets(doc, parse_result.assets, current_file_path)
  
  # 3. インラインアセットを書き換え
  rewrite_inline_assets(doc, parse_result.inline_assets, current_file_path)
  
  # 4. HTML文字列として出力
  doc.to_html
rescue => e
  raise LinkRewriterError.new(
    "リンク書き換えエラー: #{e.message}",
    current_path: current_file_path,
    original_error: e
  )
end
```

### 4.2 ページリンクの書き換え

```ruby
def rewrite_links(doc, links, current_file_path)
  links.each do |link|
    new_url = rewrite_page_link(link, current_file_path)
    link.element[link.attribute] = new_url
  end
end

def rewrite_page_link(link, current_file_path)
  # 1. 外部リンクはそのまま
  return link.url if link.external?(@base_domain)
  
  # 2. アンカーリンクはそのまま
  return link.url if link.anchor?
  
  # 3. URLをファイルパスに変換
  target_path = @path_mapper.url_to_path(link.url)
  
  # 4. マッピングできない場合
  if target_path.nil?
    logger.warn("LinkRewriter: マッピング不可 #{link.url}")
    return '#'
  end
  
  # 5. ダウンロード済みかチェック
  unless @downloaded_paths.include?(target_path)
    logger.warn("LinkRewriter: 未ダウンロード #{target_path}")
    return '#'
  end
  
  # 6. 相対パスを計算
  relative_path = calculate_relative_path(current_file_path, target_path)
  
  logger.debug("LinkRewriter: #{link.url} -> #{relative_path}")
  relative_path
end
```

### 4.3 アセットの書き換え

```ruby
def rewrite_assets(doc, assets, current_file_path)
  assets.each do |asset|
    new_url = rewrite_asset(asset, current_file_path)
    
    # srcset属性の場合は特別処理
    if asset.attribute == 'srcset'
      rewrite_srcset(asset.element, current_file_path)
    else
      asset.element[asset.attribute] = new_url
    end
  end
end

def rewrite_asset(asset, current_file_path)
  # アセットのファイルパスを取得
  target_path = @path_mapper.url_to_path(asset.url)
  
  if target_path.nil?
    logger.warn("LinkRewriter: アセットマッピング不可 #{asset.url}")
    return '#'
  end
  
  # ダウンロード予定のパスを含む
  # （アセットは後でダウンロードされるため、存在チェックは緩い）
  relative_path = calculate_relative_path(current_file_path, target_path)
  
  logger.debug("LinkRewriter: アセット #{asset.url} -> #{relative_path}")
  relative_path
end

def rewrite_srcset(element, current_file_path)
  srcset = element['srcset']
  return unless srcset
  
  # "url1 1x, url2 2x" 形式をパース
  new_entries = []
  
  srcset.split(',').each do |entry|
    parts = entry.strip.split(/\s+/)
    url = parts[0]
    descriptor = parts[1..-1].join(' ')
    
    # URLを書き換え
    target_path = @path_mapper.url_to_path(url)
    if target_path
      relative_path = calculate_relative_path(current_file_path, target_path)
      new_entries << "#{relative_path} #{descriptor}".strip
    else
      new_entries << entry.strip
    end
  end
  
  element['srcset'] = new_entries.join(', ')
end
```

### 4.4 インラインCSS/JSの書き換え

```ruby
def rewrite_inline_assets(doc, inline_assets, current_file_path)
  inline_assets.each do |inline_asset|
    case inline_asset.type
    when :inline_css
      rewrite_inline_css(inline_asset, current_file_path)
    end
  end
end

def rewrite_inline_css(inline_asset, current_file_path)
  element = inline_asset.element
  original_content = inline_asset.content
  
  # url(...)を書き換え
  new_content = original_content.gsub(/url\s*\(\s*(['"]?)(.+?)\1\s*\)/i) do
    quote = $1
    url = $2
    
    # 絶対URLに解決済みのURLから検索
    matched_url = inline_asset.urls.find { |u| u.include?(url) }
    
    if matched_url
      target_path = @path_mapper.url_to_path(matched_url)
      if target_path
        relative_path = calculate_relative_path(current_file_path, target_path)
        "url(#{quote}#{relative_path}#{quote})"
      else
        "url(#{quote}#{url}#{quote})"
      end
    else
      "url(#{quote}#{url}#{quote})"
    end
  end
  
  # 要素を更新
  if element.name == 'style'
    element.content = new_content
  else
    element['style'] = new_content
  end
end
```

## 5. PathMapper の実装

### 5.1 URLからファイルパスへのマッピング

```ruby
class PathMapper
  # @param base_url [String] ベースURL
  # @param path_mapping [Array<Hash>] 設定ファイルのpath_mapping
  # @param assets_config [Hash] アセット設定
  def initialize(base_url, path_mapping, assets_config)
    @base_url = base_url
    @path_mapping = path_mapping.map do |m|
      {
        pattern: Regexp.new(m[:pattern]),
        path_template: m[:path]
      }
    end
    @assets_config = assets_config
  end
  
  def url_to_path(url)
    uri = URI.parse(url)
    
    # 1. 外部URLはnil
    return nil unless same_host?(uri)
    
    # 2. アセット判定
    if asset_url?(url)
      return map_asset_path(url)
    end
    
    # 3. ページURLをマッピング
    query = uri.query || ''
    full_path = "#{uri.path}?#{query}"
    
    @path_mapping.each do |mapping|
      if match = mapping[:pattern].match(full_path)
        # キャプチャグループを置換
        path = mapping[:path_template].dup
        match.captures.each_with_index do |capture, index|
          path.gsub!("%{#{index + 1}}", capture)
        end
        return path
      end
    end
    
    # マッピングできない
    nil
  end
  
  private
  
  def same_host?(uri)
    base_uri = URI.parse(@base_url)
    uri.host == base_uri.host
  end
  
  def asset_url?(url)
    # 拡張子でアセット判定
    ext = File.extname(URI.parse(url).path).downcase
    ['.css', '.js', '.png', '.jpg', '.jpeg', '.gif', '.svg', '.webp'].include?(ext)
  end
  
  def map_asset_path(url)
    uri = URI.parse(url)
    filename = File.basename(uri.path)
    ext = File.extname(filename).downcase
    
    # タイプ別ディレクトリ
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
```

### 5.2 マッピング例

```ruby
# 設定
path_mapping = [
  { pattern: '\?cmd=top', path: 'index.html' },
  { pattern: '\?cmd=vlog&vil=(\d+)&turn=(\d+)', path: 'villages/%{1}/%{2}.html' }
]

mapper = PathMapper.new('http://example.com/wolf.cgi', path_mapping, assets_config)

# ページ
mapper.url_to_path('http://example.com/wolf.cgi?cmd=top')
# => 'index.html'

mapper.url_to_path('http://example.com/wolf.cgi?cmd=vlog&vil=1&turn=2')
# => 'villages/1/2.html'

# アセット
mapper.url_to_path('http://example.com/style.css')
# => 'assets/css/style.css'

mapper.url_to_path('http://example.com/images/icon.png')
# => 'assets/images/icon.png'

# 外部URL
mapper.url_to_path('http://other.com/page.html')
# => nil
```

## 6. ダウンロード済みパスの管理

### 6.1 Set での管理

```ruby
# メインループで管理
downloaded_paths = Set.new

pages.each do |url, file_path|
  # ダウンロード前にセットに追加
  downloaded_paths.add(file_path)
  
  result = fetcher.fetch(url)
  parse_result = parser.parse(result.body, url)
  
  # LinkRewriterに渡す
  rewriter = LinkRewriter.new(base_domain, path_mapper, downloaded_paths)
  rewritten_html = rewriter.rewrite(parse_result, file_path)
  
  storage.save(file_path, rewritten_html)
end
```

### 6.2 事前登録パターン

```ruby
# すべてのダウンロード予定ファイルを事前に登録
downloaded_paths = Set.new
all_pages.each { |url, path| downloaded_paths.add(path) }

# これにより、後でダウンロードするページへのリンクも正しく書き換え可能
```

## 7. エラーハンドリング

### 7.1 マッピング失敗

```ruby
# URLがマッピングできない場合
target_path = @path_mapper.url_to_path(link.url)
if target_path.nil?
  logger.warn("LinkRewriter: マッピング不可 #{link.url} -> #")
  return '#'
end
```

### 7.2 未ダウンロードページ

```ruby
# ダウンロード予定にないページへのリンク
unless @downloaded_paths.include?(target_path)
  logger.warn("LinkRewriter: 未ダウンロード #{target_path} -> #")
  return '#'
end
```

### 7.3 相対パス計算失敗

```ruby
def calculate_relative_path(from_path, to_path)
  # ...
rescue => e
  logger.error("LinkRewriter: 相対パス計算失敗 #{from_path} -> #{to_path}")
  to_path  # フォールバック：元のパスを返す
end
```

## 8. ログ出力

### 8.1 ログレベル

| レベル | 内容 |
|--------|------|
| DEBUG | 個別のリンク書き換え |
| INFO | 書き換え完了、統計情報 |
| WARN | マッピング不可、未ダウンロード |
| ERROR | 書き換え失敗 |

### 8.2 ログメッセージ例

```ruby
# DEBUG
"LinkRewriter: http://example.com/page1 -> ../page1.html"
"LinkRewriter: アセット http://example.com/style.css -> assets/css/style.css"

# INFO
"LinkRewriter: 書き換え完了 villages/1/day1.html (リンク:15, アセット:8)"

# WARN
"LinkRewriter: マッピング不可 http://example.com/unknown -> #"
"LinkRewriter: 未ダウンロード villages/999/day1.html -> #"

# ERROR
"LinkRewriter: 書き換え失敗 villages/1/day1.html - Invalid path"
```

## 9. 使用例

### 9.1 基本的な使用

```ruby
# 準備
base_domain = 'example.com'
path_mapper = PathMapper.new(base_url, path_mapping, assets_config)
downloaded_paths = Set.new(['index.html', 'villages/1/day1.html'])

# 書き換え
rewriter = LinkRewriter.new(base_domain, path_mapper, downloaded_paths)
rewritten_html = rewriter.rewrite(parse_result, 'villages/1/day1.html')

# 保存
storage.save('villages/1/day1.html', rewritten_html)
```

### 9.2 統合例

```ruby
pages = [
  { url: 'http://example.com/wolf.cgi?cmd=top', path: 'index.html' },
  { url: 'http://example.com/wolf.cgi?cmd=vlog&vil=1&turn=1', path: 'villages/1/day1.html' }
]

# 事前にすべてのパスを登録
downloaded_paths = Set.new(pages.map { |p| p[:path] })

pages.each do |page|
  # 取得
  result = fetcher.fetch(page[:url])
  utf8_html = EncodingConverter.to_utf8(result.body, encoding)
  
  # 解析
  parse_result = parser.parse(utf8_html, page[:url])
  
  # 書き換え
  rewriter = LinkRewriter.new(base_domain, path_mapper, downloaded_paths)
  rewritten_html = rewriter.rewrite(parse_result, page[:path])
  
  # 保存
  storage.save(page[:path], rewritten_html)
end
```

## 10. パフォーマンス考慮

### 10.1 相対パス計算のキャッシュ

```ruby
def initialize(base_domain, path_mapper, downloaded_paths)
  # ...
  @relative_path_cache = {}
end

def calculate_relative_path(from_path, to_path)
  cache_key = "#{from_path}::#{to_path}"
  @relative_path_cache[cache_key] ||= compute_relative_path(from_path, to_path)
end
```

### 10.2 正規表現マッチのキャッシュ

PathMapperでURLマッチング結果をキャッシュ：

```ruby
def url_to_path(url)
  @url_cache ||= {}
  @url_cache[url] ||= compute_url_to_path(url)
end
```

## 11. テストケース

### 11.1 相対パス計算

- [ ] 同じディレクトリ
- [ ] 下の階層へ
- [ ] 上の階層へ
- [ ] 異なる階層間
- [ ] 深い階層
- [ ] ルートからのパス

### 11.2 リンク書き換え

- [ ] 内部リンクを相対パスに
- [ ] 外部リンクをそのまま保持
- [ ] マッピング不可を#に
- [ ] 未ダウンロードを#に
- [ ] アンカーリンクをそのまま

### 11.3 アセット書き換え

- [ ] CSSファイル
- [ ] JavaScriptファイル
- [ ] 画像ファイル
- [ ] srcset属性
- [ ] インラインCSS

### 11.4 エッジケース

- [ ] 非常に深い階層（10階層以上）
- [ ] 同名ファイルが異なる階層に存在
- [ ] URLにクエリパラメータ
- [ ] 日本語を含むパス

## 12. 依存関係

- `pathname` (標準ライブラリ)
- `set` (標準ライブラリ)
- `uri` (標準ライブラリ)
- `Parser` クラス（ParseResult）
- `PathMapper` クラス

## 13. 実装の注意点

### 13.1 パスの正規化

```ruby
# Pathnameを使って正規化
Pathname.new('villages/1/../2/day1.html').cleanpath.to_s
# => 'villages/2/day1.html'
```

### 13.2 HTMLエスケープ

相対パスに特殊文字が含まれる場合：

```ruby
# Nokogiriが自動的にエスケープするため、通常は不要
# 日本語ファイル名の場合もNokogiriが処理
```

### 13.3 元のドキュメントの保持

```ruby
# parse_result.documentを変更すると元が壊れる
doc = parse_result.document.dup  # コピーを作成
```

## 14. 今後の拡張可能性

- CSSファイル内の@import書き換え
- JavaScriptファイル内のURL書き換え（限定的）
- 絶対URLオプション（相対/絶対を選択可能に）
- Base64エンコードオプション（小さい画像をインライン化）
- リンク検証（書き換え後のリンク切れチェック）

## 15. 次のステップ

LinkRewriterの仕様が確定したら、次は **AssetDownloader** に進みます。
AssetDownloaderはParserで抽出したアセットをダウンロードする処理を担当します。
