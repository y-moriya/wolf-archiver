# AssetDownloader 詳細仕様

## 1. 責務

Parserで抽出したアセット（CSS/JS/画像）をダウンロードし、適切なディレクトリに保存する。
重複ダウンロードを防ぎ、エラー時の処理を適切に行う。

## 2. インターフェース

### 2.1 クラス定義

```ruby
class AssetDownloader
  # 初期化
  # @param fetcher [Fetcher] HTTP取得オブジェクト
  # @param storage [Storage] ストレージオブジェクト
  # @param path_mapper [PathMapper] URLからファイルパスへのマッピング
  def initialize(fetcher, storage, path_mapper)
  
  # アセットをダウンロード
  # @param assets [Array<Asset>] アセットのリスト
  # @return [DownloadResult] ダウンロード結果
  def download(assets)
  
  # 単一のアセットをダウンロード
  # @param asset [Asset] アセット
  # @return [String, nil] 保存したファイルパス（失敗時はnil）
  def download_single(asset)
end

class DownloadResult
  attr_reader :succeeded, :failed, :skipped, :total
  
  # @param succeeded [Array<String>] 成功したファイルパスのリスト
  # @param failed [Array<Hash>] 失敗した情報のリスト（url, error含む）
  # @param skipped [Array<String>] スキップしたファイルパスのリスト
  def initialize(succeeded:, failed:, skipped:)
  
  # 成功率
  # @return [Float] 0.0〜1.0
  def success_rate
  
  # サマリーを出力
  # @return [String]
  def summary
end

class AssetDownloadError < StandardError
  attr_reader :url, :asset_type, :original_error
  
  def initialize(message, url: nil, asset_type: nil, original_error: nil)
    @url = url
    @asset_type = asset_type
    @original_error = original_error
    super(message)
  end
end
```

## 3. ダウンロード処理

### 3.1 基本的なダウンロードフロー

```ruby
def download(assets)
  succeeded = []
  failed = []
  skipped = []
  
  # URL単位で重複除去
  unique_assets = deduplicate_assets(assets)
  
  logger.info("AssetDownloader: #{unique_assets.size}件のアセットをダウンロード開始")
  
  unique_assets.each_with_index do |asset, index|
    logger.debug("AssetDownloader: 進捗 #{index + 1}/#{unique_assets.size}")
    
    begin
      result = download_single(asset)
      
      if result == :skipped
        skipped << asset.url
      elsif result
        succeeded << result
      else
        failed << { url: asset.url, error: 'Unknown error' }
      end
    rescue => e
      logger.error("AssetDownloader: ダウンロード失敗 #{asset.url} - #{e.message}")
      failed << { url: asset.url, error: e.message, type: asset.type }
    end
  end
  
  DownloadResult.new(succeeded: succeeded, failed: failed, skipped: skipped)
end
```

### 3.2 単一アセットのダウンロード

```ruby
def download_single(asset)
  # 1. URLをファイルパスにマッピング
  file_path = @path_mapper.url_to_path(asset.url)
  
  unless file_path
    logger.warn("AssetDownloader: マッピング不可 #{asset.url}")
    return nil
  end
  
  # 2. 既に存在する場合はスキップ
  if @storage.exist?(file_path)
    logger.debug("AssetDownloader: スキップ #{file_path} (既に存在)")
    return :skipped
  end
  
  # 3. ダウンロード
  result = @fetcher.fetch_binary(asset.url)
  
  unless result.success?
    logger.warn("AssetDownloader: HTTP失敗 #{asset.url} (#{result.status})")
    return nil
  end
  
  # 4. 保存
  @storage.save_binary(file_path, result.body)
  
  logger.info("AssetDownloader: 保存完了 #{file_path} (#{result.body.bytesize} bytes)")
  file_path
rescue FetchError => e
  logger.error("AssetDownloader: 取得失敗 #{asset.url} - #{e.message}")
  raise AssetDownloadError.new(
    "アセット取得失敗: #{e.message}",
    url: asset.url,
    asset_type: asset.type,
    original_error: e
  )
rescue StorageError => e
  logger.error("AssetDownloader: 保存失敗 #{file_path} - #{e.message}")
  raise AssetDownloadError.new(
    "アセット保存失敗: #{e.message}",
    url: asset.url,
    asset_type: asset.type,
    original_error: e
  )
end
```

### 3.3 重複除去

```ruby
def deduplicate_assets(assets)
  # URLで重複除去（同じURLは1回だけダウンロード）
  seen_urls = Set.new
  unique_assets = []
  
  assets.each do |asset|
    unless seen_urls.include?(asset.url)
      seen_urls.add(asset.url)
      unique_assets << asset
    end
  end
  
  logger.debug("AssetDownloader: 重複除去 #{assets.size} -> #{unique_assets.size}")
  unique_assets
end
```

## 4. DownloadResult の詳細

### 4.1 統計情報

```ruby
class DownloadResult
  def initialize(succeeded:, failed:, skipped:)
    @succeeded = succeeded
    @failed = failed
    @skipped = skipped
    @total = succeeded.size + failed.size + skipped.size
  end
  
  def success_rate
    return 1.0 if @total == 0
    @succeeded.size.to_f / (@succeeded.size + @failed.size)
  end
  
  def summary
    <<~SUMMARY
      アセットダウンロード結果:
        成功: #{@succeeded.size}件
        失敗: #{@failed.size}件
        スキップ: #{@skipped.size}件
        合計: #{@total}件
        成功率: #{(success_rate * 100).round(1)}%
    SUMMARY
  end
  
  # 失敗したアセットの詳細
  def failed_details
    @failed.map do |f|
      "  - #{f[:url]} (#{f[:type]}) : #{f[:error]}"
    end.join("\n")
  end
end
```

### 4.2 使用例

```ruby
result = downloader.download(assets)

puts result.summary
# => アセットダウンロード結果:
#      成功: 45件
#      失敗: 2件
#      スキップ: 3件
#      合計: 50件
#      成功率: 95.7%

if result.failed.any?
  puts "失敗したアセット:"
  puts result.failed_details
end
```

## 5. エラーハンドリング

### 5.1 エラー種別と対応

| エラー | 原因 | 処理 |
|--------|------|------|
| `FetchError` (404) | ファイルが存在しない | ログ出力、failedに追加、継続 |
| `FetchError` (timeout) | タイムアウト | ログ出力、failedに追加、継続 |
| `StorageError` | 保存失敗 | ログ出力、failedに追加、継続 |
| マッピング不可 | URLがマッピングできない | ログ出力、failedに追加、継続 |

**方針**: 個別のアセットダウンロード失敗で全体を停止しない

### 5.2 エラーログ

```ruby
# 404
"AssetDownloader: HTTP失敗 http://example.com/missing.png (404)"

# タイムアウト
"AssetDownloader: 取得失敗 http://example.com/slow.js - Timeout"

# 保存失敗
"AssetDownloader: 保存失敗 assets/images/icon.png - Permission denied"

# マッピング不可
"AssetDownloader: マッピング不可 http://other.com/external.css"
```

### 5.3 部分的成功の許容

```ruby
# 50件中2件失敗しても、48件は保存される
result = downloader.download(assets)

if result.failed.any?
  logger.warn("AssetDownloader: #{result.failed.size}件のダウンロードに失敗しました")
  # 失敗したアセットへのリンクは、LinkRewriterで適切に処理される
end
```

## 6. ファイル名の衝突処理

### 6.1 同名ファイルの扱い

```ruby
# 基本方針：最初にダウンロードしたものを保持
# 例：
#   http://example.com/images/icon.png -> assets/images/icon.png
#   http://example.com/other/icon.png  -> assets/images/icon.png (同じパスにマッピング)

def download_single(asset)
  file_path = @path_mapper.url_to_path(asset.url)
  
  # 既に存在する場合はスキップ
  if @storage.exist?(file_path)
    logger.debug("AssetDownloader: スキップ #{file_path} (既に存在)")
    return :skipped
  end
  
  # ... ダウンロード処理 ...
end
```

**注意**: 異なるURLが同じファイル名にマッピングされる場合、最初のものが優先される。
これはPathMapperの設計による。

### 6.2 将来的な改善案

ハッシュベースのファイル名を使用：

```ruby
# 現在（シンプル）：
# http://example.com/style.css -> assets/css/style.css

# 将来（ハッシュ）：
# http://example.com/style.css -> assets/css/style_a1b2c3d4.css
# http://other.com/style.css   -> assets/css/style_e5f6g7h8.css
```

**現時点では不要**（シンプルさを優先）

## 7. ログ出力

### 7.1 ログレベル

| レベル | 内容 |
|--------|------|
| DEBUG | 個別のダウンロード、進捗、スキップ |
| INFO | ダウンロード開始、保存完了、結果サマリー |
| WARN | HTTP失敗、マッピング不可、部分的失敗 |
| ERROR | 取得失敗、保存失敗 |

### 7.2 ログメッセージ例

```ruby
# DEBUG
"AssetDownloader: 重複除去 52 -> 48"
"AssetDownloader: 進捗 15/48"
"AssetDownloader: スキップ assets/css/style.css (既に存在)"

# INFO
"AssetDownloader: 48件のアセットをダウンロード開始"
"AssetDownloader: 保存完了 assets/images/icon.png (8192 bytes)"
"AssetDownloader: ダウンロード完了 - 成功:45, 失敗:2, スキップ:3"

# WARN
"AssetDownloader: HTTP失敗 http://example.com/missing.png (404)"
"AssetDownloader: マッピング不可 http://other.com/external.css"
"AssetDownloader: 2件のダウンロードに失敗しました"

# ERROR
"AssetDownloader: 取得失敗 http://example.com/slow.js - Timeout"
"AssetDownloader: 保存失敗 assets/images/icon.png - Permission denied"
```

## 8. 使用例

### 8.1 基本的な使用

```ruby
# 準備
fetcher = Fetcher.new(base_url, rate_limiter)
storage = Storage.new('archive/site_a')
path_mapper = PathMapper.new(base_url, path_mapping, assets_config)
downloader = AssetDownloader.new(fetcher, storage, path_mapper)

# HTMLを解析してアセット抽出
parse_result = parser.parse(html, url)

# アセットをダウンロード
result = downloader.download(parse_result.assets)

# 結果を表示
puts result.summary

if result.failed.any?
  puts "\n失敗したアセット:"
  puts result.failed_details
end
```

### 8.2 複数ページの統合

```ruby
all_assets = []

pages.each do |url|
  result = fetcher.fetch(url)
  parse_result = parser.parse(result.body, url)
  all_assets.concat(parse_result.assets)
end

# すべてのアセットをまとめてダウンロード（重複は自動除去）
result = downloader.download(all_assets)

logger.info("全ページのアセットダウンロード完了: #{result.summary}")
```

### 8.3 進捗表示との連携

```ruby
require 'tty-progressbar'

def download_with_progress(assets)
  unique_assets = deduplicate_assets(assets)
  progressbar = TTY::ProgressBar.new(
    "ダウンロード [:bar] :current/:total (:percent)",
    total: unique_assets.size
  )
  
  succeeded = []
  failed = []
  skipped = []
  
  unique_assets.each do |asset|
    begin
      result = download_single(asset)
      
      case result
      when :skipped
        skipped << asset.url
      when String
        succeeded << result
      else
        failed << { url: asset.url, error: 'Unknown error' }
      end
    rescue => e
      failed << { url: asset.url, error: e.message, type: asset.type }
    ensure
      progressbar.advance
    end
  end
  
  DownloadResult.new(succeeded: succeeded, failed: failed, skipped: skipped)
end
```

## 9. パフォーマンス考慮

### 9.1 重複ダウンロードの防止

```ruby
# URL単位で重複除去
def deduplicate_assets(assets)
  seen_urls = Set.new
  assets.reject do |asset|
    if seen_urls.include?(asset.url)
      true
    else
      seen_urls.add(asset.url)
      false
    end
  end
end
```

### 9.2 既存ファイルのチェック

```ruby
# Storage#exist?を使用してファイルシステムをチェック
if @storage.exist?(file_path)
  return :skipped
end
```

### 9.3 バッチダウンロード

現状は順次ダウンロード（RateLimiterによる制御）。
将来的に並行ダウンロードを追加する場合：

```ruby
# 参考：並行ダウンロード（現時点では不要）
def download_parallel(assets, max_threads: 5)
  queue = Queue.new
  assets.each { |asset| queue << asset }
  
  threads = max_threads.times.map do
    Thread.new do
      while asset = queue.pop(true) rescue nil
        download_single(asset)
      end
    end
  end
  
  threads.each(&:join)
end
```

## 10. テストケース

### 10.1 正常系

- [ ] 単一アセットのダウンロード
- [ ] 複数アセットのダウンロード
- [ ] CSS/JS/画像のダウンロード
- [ ] 重複URLの除去
- [ ] 既存ファイルのスキップ
- [ ] DownloadResultの統計情報
- [ ] 成功率の計算

### 10.2 異常系

- [ ] 404エラー → failedに追加、継続
- [ ] タイムアウト → failedに追加、継続
- [ ] 保存失敗 → failedに追加、継続
- [ ] マッピング不可 → failedに追加、継続
- [ ] すべて失敗 → success_rate = 0.0

### 10.3 エッジケース

- [ ] 0件のアセット
- [ ] すべてスキップ（既存）
- [ ] 同名ファイルが異なるURLから
- [ ] 非常に大きなファイル（100MB以上）
- [ ] Content-Typeが不正
- [ ] 拡張子なしのURL

## 11. 依存関係

- `Fetcher` クラス
- `Storage` クラス
- `PathMapper` クラス
- `Parser` クラス（Asset）
- `set` (標準ライブラリ)

## 12. 実装の注意点

### 12.1 エラー伝播

```ruby
# 個別のエラーで全体を停止しない
begin
  download_single(asset)
rescue => e
  # ログ出力して継続
  logger.error("...")
  failed << { ... }
  # raiseしない
end
```

### 12.2 バイナリデータの扱い

```ruby
# Fetcherでバイナリとして取得
result = @fetcher.fetch_binary(asset.url)

# Storageでバイナリとして保存
@storage.save_binary(file_path, result.body)

# エンコーディング変換は不要
```

### 12.3 メモリ管理

大量のアセット（1000件以上）をダウンロードする場合、ダウンロード結果をすべてメモリに保持しない工夫が必要かもしれない。

```ruby
# 現状（シンプル）：
succeeded = []
assets.each { |a| succeeded << download_single(a) }

# 将来（メモリ効率）：
File.open('download_log.txt', 'w') do |log|
  assets.each do |asset|
    result = download_single(asset)
    log.puts(result) if result
  end
end
```

**現時点では不要**（通常は数十〜数百件程度）

## 13. 統合例

### 13.1 メインワークフロー

```ruby
# 1. ページをダウンロード
pages.each do |page|
  result = fetcher.fetch(page[:url])
  utf8_html = EncodingConverter.to_utf8(result.body, encoding)
  
  # 2. 解析
  parse_result = parser.parse(utf8_html, page[:url])
  
  # 3. アセットをダウンロード
  download_result = asset_downloader.download(parse_result.assets)
  
  if download_result.failed.any?
    logger.warn("一部のアセットダウンロードに失敗: #{download_result.failed.size}件")
  end
  
  # 4. リンク書き換え
  rewriter = LinkRewriter.new(base_domain, path_mapper, downloaded_paths)
  rewritten_html = rewriter.rewrite(parse_result, page[:path])
  
  # 5. 保存
  storage.save(page[:path], rewritten_html)
end
```

### 13.2 2パスアプローチ

```ruby
# パス1: すべてのページを解析してアセットを収集
all_assets = []
pages.each do |page|
  result = fetcher.fetch(page[:url])
  parse_result = parser.parse(result.body, page[:url])
  all_assets.concat(parse_result.assets)
end

# まとめてアセットをダウンロード
download_result = asset_downloader.download(all_assets)
logger.info(download_result.summary)

# パス2: ページを書き換えて保存
pages.each do |page|
  # ... リンク書き換えと保存 ...
end
```

## 14. 今後の拡張可能性

- 並行ダウンロード対応
- リトライ処理（指数バックオフ）
- ダウンロードキャッシュ（再実行時の高速化）
- ファイルハッシュベースの重複検出
- プログレッシブダウンロード（大容量ファイル）
- 帯域制限
- ダウンロード統計（合計サイズ、平均速度など）

## 15. 次のステップ

AssetDownloaderの仕様が確定したら、最後に **WolfArchiver（メインクラス）** に進みます。
WolfArchiverはすべてのモジュールを統合し、CLIからの実行を制御します。
