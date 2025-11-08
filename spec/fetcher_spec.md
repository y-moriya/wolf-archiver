# Fetcher 詳細仕様

## 1. 責務

HTTPリクエストを実行し、レスポンスを取得する。
RateLimiterと連携してアクセス間隔を制御し、エラーハンドリングを行う。

## 2. インターフェース

### 2.1 クラス定義

```ruby
class Fetcher
  # 初期化
  # @param base_url [String] ベースURL
  # @param rate_limiter [RateLimiter] レート制限オブジェクト
  # @param timeout [Integer] タイムアウト秒数（デフォルト: 30）
  # @param user_agent [String] User-Agentヘッダー
  def initialize(base_url, rate_limiter, timeout: 30, user_agent: nil)
  
  # URLからコンテンツを取得
  # @param path [String] パス（クエリパラメータ含む）
  # @return [FetchResult] 取得結果
  # @raise [FetchError] 取得失敗時
  def fetch(path)
  
  # バイナリコンテンツを取得（画像など）
  # @param url [String] 完全なURL
  # @return [FetchResult] 取得結果
  # @raise [FetchError] 取得失敗時
  def fetch_binary(url)
end

class FetchResult
  attr_reader :body, :status, :headers, :url, :content_type
  
  # @param body [String] レスポンスボディ
  # @param status [Integer] HTTPステータスコード
  # @param headers [Hash] レスポンスヘッダー
  # @param url [String] リクエストURL
  def initialize(body:, status:, headers:, url:)
  
  # 取得成功か
  # @return [Boolean]
  def success?
  
  # HTML/テキストコンテンツか
  # @return [Boolean]
  def text?
  
  # バイナリコンテンツか
  # @return [Boolean]
  def binary?
end

class FetchError < StandardError
  attr_reader :url, :status, :original_error
  
  def initialize(message, url: nil, status: nil, original_error: nil)
    @url = url
    @status = status
    @original_error = original_error
    super(message)
  end
end
```

## 3. 取得処理の詳細

### 3.1 基本的な取得フロー

```ruby
def fetch(path)
  url = build_url(path)
  
  # 1. レート制限による待機
  @rate_limiter.wait
  
  # 2. HTTPリクエスト実行
  response = @client.get(url)
  
  # 3. 結果を返す
  FetchResult.new(
    body: response.body,
    status: response.status,
    headers: response.headers,
    url: url
  )
rescue Faraday::TimeoutError => e
  raise FetchError.new("タイムアウト: #{url}", url: url, original_error: e)
rescue Faraday::ConnectionFailed => e
  raise FetchError.new("接続失敗: #{url}", url: url, original_error: e)
rescue Faraday::Error => e
  raise FetchError.new("HTTP取得エラー: #{e.message}", url: url, original_error: e)
end
```

### 3.2 URL構築

```ruby
def build_url(path)
  # pathが既に完全なURLの場合
  return path if path.start_with?('http://', 'https://')
  
  # base_urlとpathを結合
  uri = URI.parse(@base_url)
  
  # pathがクエリパラメータのみの場合
  if path.start_with?('?')
    "#{uri.scheme}://#{uri.host}:#{uri.port}#{uri.path}#{path}"
  else
    # 通常のパス結合
    File.join(@base_url, path)
  end
end
```

### 3.3 バイナリ取得

```ruby
def fetch_binary(url)
  @rate_limiter.wait
  
  response = @client.get(url) do |req|
    req.options.timeout = @timeout
  end
  
  # バイナリデータとして扱う
  FetchResult.new(
    body: response.body.force_encoding('BINARY'),
    status: response.status,
    headers: response.headers,
    url: url
  )
rescue => e
  raise FetchError.new("バイナリ取得エラー: #{e.message}", url: url, original_error: e)
end
```

## 4. Faradayクライアント設定

### 4.1 初期化

```ruby
def initialize(base_url, rate_limiter, timeout: 30, user_agent: nil)
  @base_url = base_url
  @rate_limiter = rate_limiter
  @timeout = timeout
  @user_agent = user_agent || default_user_agent
  
  @client = Faraday.new do |conn|
    # タイムアウト設定
    conn.options.timeout = @timeout
    conn.options.open_timeout = 10
    
    # リダイレクト追従
    conn.response :follow_redirects, limit: 5
    
    # User-Agent設定
    conn.headers['User-Agent'] = @user_agent
    
    # アダプター
    conn.adapter Faraday.default_adapter
  end
end

def default_user_agent
  "WolfArchiver/1.0 (Ruby/#{RUBY_VERSION})"
end
```

### 4.2 ヘッダー設定

デフォルトで設定するヘッダー：

| ヘッダー | 値 | 理由 |
|---------|-----|------|
| User-Agent | `WolfArchiver/1.0` | ボット識別 |
| Accept | `text/html,application/xhtml+xml,*/*` | HTML優先 |
| Accept-Encoding | `gzip, deflate` | 圧縮対応 |
| Accept-Language | `ja,en` | 日本語優先 |

```ruby
conn.headers['Accept'] = 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8'
conn.headers['Accept-Encoding'] = 'gzip, deflate'
conn.headers['Accept-Language'] = 'ja,en;q=0.9'
```

## 5. エラーハンドリング

### 5.1 HTTPステータスコード

| ステータス | 処理 |
|-----------|------|
| 200 OK | 正常終了 |
| 301/302 | 自動リダイレクト（Faradayが処理） |
| 404 Not Found | FetchErrorを投げる |
| 500-599 | FetchErrorを投げる |
| タイムアウト | FetchErrorを投げる |
| 接続失敗 | FetchErrorを投げる |

### 5.2 エラーメッセージ

```ruby
case response.status
when 404
  raise FetchError.new("ページが見つかりません: #{url}", url: url, status: 404)
when 500..599
  raise FetchError.new("サーバーエラー (#{response.status}): #{url}", url: url, status: response.status)
end
```

### 5.3 リトライ処理

**現仕様ではリトライしない**（仕様で明記済み）

将来的に追加する場合の考慮点：
```ruby
# 参考：リトライ実装例（現時点では不要）
def fetch_with_retry(path, max_retries: 3)
  retries = 0
  begin
    fetch(path)
  rescue FetchError => e
    retries += 1
    if retries < max_retries && retriable_error?(e)
      sleep(2 ** retries)  # 指数バックオフ
      retry
    else
      raise
    end
  end
end
```

## 6. FetchResult の詳細

### 6.1 content_typeの判定

```ruby
class FetchResult
  def initialize(body:, status:, headers:, url:)
    @body = body
    @status = status
    @headers = headers
    @url = url
    @content_type = headers['content-type'] || headers['Content-Type'] || ''
  end
  
  def success?
    @status >= 200 && @status < 300
  end
  
  def text?
    @content_type.start_with?('text/') ||
    @content_type.include?('html') ||
    @content_type.include?('xml')
  end
  
  def binary?
    !text?
  end
end
```

### 6.2 ファイル拡張子の推測

```ruby
class FetchResult
  # Content-Typeからファイル拡張子を推測
  # @return [String, nil]
  def suggested_extension
    case @content_type
    when /image\/jpeg/
      '.jpg'
    when /image\/png/
      '.png'
    when /image\/gif/
      '.gif'
    when /image\/svg/
      '.svg'
    when /text\/css/
      '.css'
    when /javascript/
      '.js'
    when /text\/html/
      '.html'
    else
      nil
    end
  end
end
```

## 7. ログ出力

### 7.1 ログレベル

| レベル | 内容 |
|--------|------|
| DEBUG | リクエスト開始、URL、レスポンスサイズ |
| INFO | 取得成功 |
| WARN | リダイレクト |
| ERROR | 取得失敗 |

### 7.2 ログメッセージ例

```ruby
# DEBUG
"Fetcher: リクエスト開始 GET http://example.com/page1"
"Fetcher: レスポンス受信 200 OK (12345 bytes)"

# INFO
"Fetcher: 取得成功 http://example.com/page1 (200 OK)"

# WARN
"Fetcher: リダイレクト 301 -> http://example.com/page2"

# ERROR
"Fetcher: 取得失敗 404 Not Found - http://example.com/missing"
"Fetcher: タイムアウト - http://example.com/slow"
```

## 8. 使用例

### 8.1 基本的な使用

```ruby
rate_limiter = RateLimiter.new(2.0)
fetcher = Fetcher.new('http://example.com/wolf.cgi', rate_limiter)

# HTMLページを取得
result = fetcher.fetch('?cmd=top')
puts result.body
puts result.status  # => 200
puts result.success?  # => true

# 画像を取得
image_result = fetcher.fetch_binary('http://example.com/images/icon.png')
File.binwrite('icon.png', image_result.body)
```

### 8.2 エラーハンドリング

```ruby
begin
  result = fetcher.fetch('?cmd=vlog&vil=999')
rescue FetchError => e
  logger.error("取得失敗: #{e.message}")
  logger.error("URL: #{e.url}")
  logger.error("ステータス: #{e.status}") if e.status
  # 次のURLに進む
  next
end
```

### 8.3 EncodingConverterとの連携

```ruby
result = fetcher.fetch('?cmd=top')

if result.success? && result.text?
  # Shift_JISからUTF-8に変換
  utf8_content = EncodingConverter.to_utf8(result.body, 'Shift_JIS')
  storage.save('index.html', utf8_content)
end
```

## 9. セキュリティ考慮

### 9.1 SSRF対策

内部ネットワークへのアクセスを防ぐ（オプション）：

```ruby
def validate_url(url)
  uri = URI.parse(url)
  
  # プライベートIPアドレスへのアクセスを禁止
  if private_ip?(uri.host)
    raise FetchError.new("プライベートIPへのアクセスは禁止されています: #{uri.host}")
  end
end

def private_ip?(host)
  # 127.0.0.1, 10.x.x.x, 172.16-31.x.x, 192.168.x.x
  return false unless host
  
  IPAddr.new(host).private? rescue false
end
```

**現仕様では実装不要**（信頼できる設定ファイルのURLのみアクセス）

### 9.2 リダイレクト制限

無限リダイレクトを防ぐ：

```ruby
conn.response :follow_redirects, limit: 5
```

既にFaradayで設定済み。

## 10. パフォーマンス考慮

### 10.1 接続の再利用

Faradayは内部で接続プールを管理するため、同一ホストへの複数リクエストで接続が再利用される。

### 10.2 タイムアウト設定

| タイムアウト | デフォルト値 | 説明 |
|-------------|------------|------|
| open_timeout | 10秒 | 接続確立のタイムアウト |
| timeout | 30秒 | レスポンス受信のタイムアウト |

### 10.3 メモリ使用

大容量レスポンス（数MB以上の画像など）は一度にメモリに読み込むため注意。
通常のHTMLページは問題なし。

## 11. テストケース

### 11.1 正常系

- [ ] 200 OKのレスポンスを正しく取得
- [ ] クエリパラメータ付きのURLを正しく構築
- [ ] 完全なURLを渡した場合もそのまま使用
- [ ] バイナリコンテンツを正しく取得
- [ ] RateLimiterが呼ばれる
- [ ] リダイレクトを自動追従
- [ ] Content-Typeを正しく判定

### 11.2 異常系

- [ ] 404 Not Found → FetchError
- [ ] 500 Internal Server Error → FetchError
- [ ] タイムアウト → FetchError
- [ ] 接続失敗 → FetchError
- [ ] 不正なURL → FetchError
- [ ] リダイレクト上限超過 → FetchError

### 11.3 エッジケース

- [ ] 空のレスポンスボディ
- [ ] 巨大なレスポンス（10MB以上）
- [ ] Content-Typeヘッダーがない
- [ ] 文字化けしたレスポンス（エンコーディング処理前）

## 12. 依存関係

- `faraday` gem
- `uri` (標準ライブラリ)
- `RateLimiter` クラス

## 13. 実装の注意点

### 13.1 エンコーディング処理の分離

Fetcherはバイナリデータとして取得し、エンコーディング変換は行わない。
変換はEncodingConverterの責務。

```ruby
# Fetcherの責務：バイト列を取得
result = fetcher.fetch('?cmd=top')
raw_bytes = result.body  # Shift_JISのバイト列

# EncodingConverterの責務：文字列に変換
utf8_string = EncodingConverter.to_utf8(raw_bytes, 'Shift_JIS')
```

### 13.2 パスとURLの区別

```ruby
# パス（base_urlと結合）
fetcher.fetch('?cmd=top')
fetcher.fetch('/static/style.css')

# 完全なURL（そのまま使用）
fetcher.fetch_binary('http://example.com/images/logo.png')
```

### 13.3 レスポンスボディのコピー

Faradayのレスポンスボディは文字列だが、エンコーディング情報が付いている場合がある：

```ruby
# エンコーディング情報をクリア
body = response.body.dup.force_encoding('BINARY')
```

## 14. 今後の拡張可能性

- リトライ処理の追加
- 並行ダウンロード対応（接続プール管理）
- キャッシュ機構（同一URLの重複取得防止）
- 帯域制限（ダウンロード速度制限）
- プログレス通知（大容量ファイルのダウンロード進捗）
- プロキシサポート

## 15. 次のステップ

Fetcherの仕様が確定したら、次は **Storage** に進みます。
