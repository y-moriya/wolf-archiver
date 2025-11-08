# WolfArchiver 詳細仕様

## 1. 責務

すべてのモジュールを統合し、アーカイブ処理全体を制御する。
CLI引数の処理、設定読み込み、ワークフロー実行、エラーハンドリングを担当する。

## 2. アーキテクチャ

### 2.1 全体構成

```
CLI (Thor)
  ↓
WolfArchiver (メインクラス)
  ├─ ConfigLoader
  ├─ RateLimiter
  ├─ Fetcher
  ├─ Parser
  ├─ EncodingConverter
  ├─ Storage
  ├─ PathMapper
  ├─ LinkRewriter
  └─ AssetDownloader
```

### 2.2 処理フロー

```
1. CLI引数解析 (Thor)
2. 設定ファイル読み込み (ConfigLoader)
3. 各モジュールの初期化
4. ダウンロード対象ページの決定
5. ページごとの処理ループ:
   a. HTMLダウンロード (Fetcher)
   b. エンコーディング変換 (EncodingConverter)
   c. HTML解析 (Parser)
   d. アセットダウンロード (AssetDownloader)
   e. リンク書き換え (LinkRewriter)
   f. 保存 (Storage)
6. 結果サマリー表示
```

## 3. インターフェース

### 3.1 CLIインターフェース（Thor）

```ruby
class WolfArchiverCLI < Thor
  desc "fetch SITE_NAME", "指定されたサイトをアーカイブ"
  option :output, aliases: '-o', type: :string, default: './archive', desc: '出力ディレクトリ'
  option :config, aliases: '-c', type: :string, default: 'config/sites.yml', desc: '設定ファイル'
  option :village_ids, type: :array, desc: '取得する村IDのリスト'
  option :user_ids, type: :array, desc: '取得するユーザーIDのリスト'
  option :auto_discover, type: :boolean, default: false, desc: '一覧ページから自動取得'
  option :users_only, type: :boolean, default: false, desc: 'ユーザーページのみ取得'
  option :villages_only, type: :boolean, default: false, desc: '村ページのみ取得'
  option :static_only, type: :boolean, default: false, desc: '静的ページのみ取得'
  def fetch(site_name)
    archiver = WolfArchiver.new(
      site_name: site_name,
      config_path: options[:config],
      output_dir: options[:output]
    )
    
    archiver.run(
      village_ids: options[:village_ids],
      user_ids: options[:user_ids],
      auto_discover: options[:auto_discover],
      users_only: options[:users_only],
      villages_only: options[:villages_only],
      static_only: options[:static_only]
    )
  rescue => e
    error "エラーが発生しました: #{e.message}"
    error e.backtrace.join("\n") if ENV['DEBUG']
    exit 1
  end
  
  desc "version", "バージョンを表示"
  def version
    puts "WolfArchiver #{WolfArchiver::VERSION}"
  end
  
  desc "list", "設定されているサイトの一覧を表示"
  option :config, aliases: '-c', type: :string, default: 'config/sites.yml', desc: '設定ファイル'
  def list
    loader = ConfigLoader.new(options[:config])
    
    puts "設定されているサイト:"
    loader.site_names.each do |name|
      site = loader.site(name)
      puts "  - #{name}: #{site.name} (#{site.base_url})"
    end
  end
end
```

### 3.2 メインクラス

```ruby
class WolfArchiver
  VERSION = '1.0.0'
  
  attr_reader :site_name, :config, :output_dir
  
  # 初期化
  # @param site_name [String] サイト名
  # @param config_path [String] 設定ファイルパス
  # @param output_dir [String] 出力ディレクトリ
  def initialize(site_name:, config_path:, output_dir:)
  
  # アーカイブ実行
  # @param village_ids [Array<String>, nil] 村IDリスト
  # @param user_ids [Array<String>, nil] ユーザーIDリスト
  # @param auto_discover [Boolean] 自動検出
  # @param users_only [Boolean] ユーザーのみ
  # @param villages_only [Boolean] 村のみ
  # @param static_only [Boolean] 静的ページのみ
  # @return [ArchiveResult] 実行結果
  def run(village_ids: nil, user_ids: nil, auto_discover: false, 
          users_only: false, villages_only: false, static_only: false)
  
  private
  
  # モジュールの初期化
  def setup_modules
  
  # ダウンロード対象ページの決定
  def determine_pages(options)
  
  # ページのダウンロードと処理
  def process_pages(pages)
  
  # 村一覧から村IDを取得
  def discover_village_ids
  
  # ユーザー一覧からユーザーIDを取得
  def discover_user_ids
end

class ArchiveResult
  attr_reader :total_pages, :succeeded_pages, :failed_pages
  attr_reader :total_assets, :succeeded_assets, :failed_assets
  attr_reader :start_time, :end_time
  
  def duration
  def summary
end
```

## 4. 実装詳細

### 4.1 初期化処理

```ruby
def initialize(site_name:, config_path:, output_dir:)
  @site_name = site_name
  @output_dir = output_dir
  
  # ログ設定
  setup_logger
  
  logger.info("WolfArchiver #{VERSION} 起動")
  logger.info("サイト: #{site_name}")
  logger.info("出力先: #{output_dir}")
  
  # 設定読み込み
  @config_loader = ConfigLoader.new(config_path)
  @site_config = @config_loader.site(site_name)
  
  logger.info("サイト設定: #{@site_config.name}")
  logger.info("ベースURL: #{@site_config.base_url}")
  logger.info("エンコーディング: #{@site_config.encoding}")
  
  # モジュール初期化
  setup_modules
  
  # ダウンロード済みパスの管理
  @downloaded_paths = Set.new
  
  # 統計情報
  @stats = {
    pages: { total: 0, succeeded: 0, failed: 0 },
    assets: { total: 0, succeeded: 0, failed: 0, skipped: 0 }
  }
  
  @start_time = Time.now
end
```

### 4.2 モジュール初期化

```ruby
def setup_modules
  # Storage
  site_output_dir = File.join(@output_dir, @site_name)
  @storage = Storage.new(site_output_dir)
  
  # RateLimiter
  @rate_limiter = RateLimiter.new(
    @site_config.actual_wait_time,
    enabled: !@site_config.localhost?
  )
  
  # Fetcher
  @fetcher = Fetcher.new(
    @site_config.base_url,
    @rate_limiter,
    timeout: 30
  )
  
  # Parser
  base_domain = URI.parse(@site_config.base_url).host
  @parser = Parser.new(@site_config.base_url)
  
  # PathMapper
  @path_mapper = PathMapper.new(
    @site_config.base_url,
    @site_config.path_mapping,
    @site_config.assets
  )
  
  # AssetDownloader
  @asset_downloader = AssetDownloader.new(
    @fetcher,
    @storage,
    @path_mapper
  )
  
  logger.info("モジュール初期化完了")
end
```

### 4.3 ダウンロード対象の決定

```ruby
def determine_pages(options)
  pages = []
  
  # 静的ページのみ
  if options[:static_only]
    pages.concat(build_static_pages)
    return pages
  end
  
  # ユーザーのみ
  if options[:users_only]
    user_ids = options[:user_ids] || (options[:auto_discover] ? discover_user_ids : [])
    pages.concat(build_user_pages(user_ids))
    return pages
  end
  
  # 村のみ
  if options[:villages_only]
    village_ids = options[:village_ids] || (options[:auto_discover] ? discover_village_ids : [])
    pages.concat(build_village_pages(village_ids))
    return pages
  end
  
  # 全部（デフォルト）
  pages << build_index_page
  
  # 村
  if options[:auto_discover] || options[:village_ids]
    village_ids = options[:village_ids] || discover_village_ids
    pages.concat(build_village_pages(village_ids))
  end
  
  # ユーザー
  if options[:auto_discover] || options[:user_ids]
    user_ids = options[:user_ids] || discover_user_ids
    pages.concat(build_user_pages(user_ids))
  end
  
  # 静的ページ
  pages.concat(build_static_pages)
  
  pages
end
```

### 4.4 ページ構築メソッド

```ruby
def build_index_page
  query = @site_config.pages[:index]
  { url: "#{@site_config.base_url}#{query}", path: 'index.html' }
end

def build_village_pages(village_ids)
  pages = []
  
  # 村一覧ページ
  if query = @site_config.pages[:village_list]
    pages << { url: "#{@site_config.base_url}#{query}", path: 'village_list.html' }
  end
  
  # 各村のページ
  village_ids.each do |village_id|
    # 村の日数を取得（または設定から）
    max_days = discover_village_days(village_id)
    
    (1..max_days).each do |day|
      query = @site_config.pages[:village]
        .gsub('%{village_id}', village_id.to_s)
        .gsub('%{date}', day.to_s)
      
      url = "#{@site_config.base_url}#{query}"
      path = "villages/#{village_id}/day#{day}.html"
      
      pages << { url: url, path: path }
    end
  end
  
  pages
end

def build_user_pages(user_ids)
  pages = []
  
  # ユーザー一覧ページ
  if query = @site_config.pages[:user_list]
    pages << { url: "#{@site_config.base_url}#{query}", path: 'users/index.html' }
  end
  
  # 各ユーザーのページ
  user_ids.each do |user_id|
    query = @site_config.pages[:user].gsub('%{user_id}', user_id.to_s)
    url = "#{@site_config.base_url}#{query}"
    path = "users/#{user_id}.html"
    
    pages << { url: url, path: path }
  end
  
  pages
end

def build_static_pages
  pages = []
  
  @site_config.pages[:static]&.each do |query|
    # クエリからファイル名を推測
    cmd = query.match(/cmd=(\w+)/)[1] rescue 'unknown'
    url = "#{@site_config.base_url}#{query}"
    path = "static/#{cmd}.html"
    
    pages << { url: url, path: path }
  end
  
  pages
end
```

### 4.5 自動検出メソッド

```ruby
def discover_village_ids
  logger.info("村一覧から村IDを自動検出中...")
  
  list_query = @site_config.pages[:village_list]
  return [] unless list_query
  
  # 村一覧ページを取得
  result = @fetcher.fetch(list_query)
  utf8_html = EncodingConverter.to_utf8(result.body, @site_config.encoding)
  parse_result = @parser.parse(utf8_html, "#{@site_config.base_url}#{list_query}")
  
  # 村ページへのリンクから村IDを抽出
  village_ids = Set.new
  base_domain = URI.parse(@site_config.base_url).host
  
  parse_result.links.each do |link|
    next unless link.internal?(base_domain)
    
    # URLから村IDを抽出（vil=123のようなパターン）
    if match = link.url.match(/vil=(\d+)/)
      village_ids.add(match[1].to_i)
    end
  end
  
  village_ids = village_ids.to_a.sort
  logger.info("#{village_ids.size}件の村を検出: #{village_ids.join(', ')}")
  
  village_ids
rescue => e
  logger.error("村ID自動検出エラー: #{e.message}")
  []
end

def discover_user_ids
  logger.info("ユーザー一覧からユーザーIDを自動検出中...")
  
  list_query = @site_config.pages[:user_list]
  return [] unless list_query
  
  # ユーザー一覧ページを取得
  result = @fetcher.fetch(list_query)
  utf8_html = EncodingConverter.to_utf8(result.body, @site_config.encoding)
  parse_result = @parser.parse(utf8_html, "#{@site_config.base_url}#{list_query}")
  
  # ユーザーページへのリンクからユーザーIDを抽出
  user_ids = Set.new
  base_domain = URI.parse(@site_config.base_url).host
  
  parse_result.links.each do |link|
    next unless link.internal?(base_domain)
    
    # URLからユーザーIDを抽出（uid=123のようなパターン）
    if match = link.url.match(/uid=(\d+)/)
      user_ids.add(match[1].to_i)
    end
  end
  
  user_ids = user_ids.to_a.sort
  logger.info("#{user_ids.size}名のユーザーを検出: #{user_ids.join(', ')}")
  
  user_ids
rescue => e
  logger.error("ユーザーID自動検出エラー: #{e.message}")
  []
end

def discover_village_days(village_id)
  # 村のページを1日目から順に取得し、404になるまで続ける
  # または設定ファイルで最大日数を指定
  
  # シンプルな実装: 固定値（または設定から）
  max_days = @site_config.dig(:villages, :max_days) || 10
  
  # より高度な実装: 実際にアクセスして確認
  # (1..100).each do |day|
  #   url = build_village_url(village_id, day)
  #   result = @fetcher.fetch(url)
  #   break if result.status == 404
  #   max_days = day
  # end
  
  max_days
end
```

### 4.6 ページ処理ループ

```ruby
def process_pages(pages)
  logger.info("#{pages.size}ページの処理を開始")
  
  # プログレスバー
  progressbar = TTY::ProgressBar.new(
    "[:bar] :current/:total :percent | :page",
    total: pages.size,
    width: 50
  )
  
  # 事前にすべてのパスを登録（LinkRewriter用）
  pages.each { |page| @downloaded_paths.add(page[:path]) }
  
  pages.each_with_index do |page, index|
    begin
      progressbar.log("処理中: #{page[:path]}")
      progressbar.advance(page: File.basename(page[:path]))
      
      process_single_page(page)
      
      @stats[:pages][:succeeded] += 1
    rescue => e
      logger.error("ページ処理エラー: #{page[:url]} - #{e.message}")
      logger.debug(e.backtrace.join("\n"))
      
      @stats[:pages][:failed] += 1
    end
    
    @stats[:pages][:total] += 1
  end
  
  progressbar.finish
end

def process_single_page(page)
  # スキップチェック
  if @storage.exist?(page[:path])
    logger.info("スキップ: #{page[:path]} (既に存在)")
    return
  end
  
  # 1. HTMLダウンロード
  logger.debug("ダウンロード: #{page[:url]}")
  result = @fetcher.fetch(page[:url])
  
  unless result.success?
    raise "HTTP失敗: #{result.status}"
  end
  
  # 2. エンコーディング変換
  utf8_html = EncodingConverter.to_utf8(result.body, @site_config.encoding)
  
  # 3. HTML解析
  parse_result = @parser.parse(utf8_html, page[:url])
  
  logger.debug("リンク: #{parse_result.links.size}件")
  logger.debug("アセット: #{parse_result.assets.size}件")
  
  # 4. アセットダウンロード
  if @site_config.assets[:download] && parse_result.assets.any?
    download_result = @asset_downloader.download(parse_result.assets)
    
    @stats[:assets][:total] += download_result.total
    @stats[:assets][:succeeded] += download_result.succeeded.size
    @stats[:assets][:failed] += download_result.failed.size
    @stats[:assets][:skipped] += download_result.skipped.size
    
    if download_result.failed.any?
      logger.warn("一部のアセットダウンロードに失敗: #{download_result.failed.size}件")
    end
  end
  
  # 5. リンク書き換え
  base_domain = URI.parse(@site_config.base_url).host
  rewriter = LinkRewriter.new(base_domain, @path_mapper, @downloaded_paths)
  rewritten_html = rewriter.rewrite(parse_result, page[:path])
  
  # 6. 保存
  @storage.save(page[:path], rewritten_html)
  
  logger.info("保存完了: #{page[:path]}")
end
```

### 4.7 実行メソッド

```ruby
def run(options)
  begin
    # ダウンロード対象を決定
    pages = determine_pages(options)
    
    if pages.empty?
      logger.warn("ダウンロード対象がありません")
      return build_result
    end
    
    logger.info("ダウンロード対象: #{pages.size}ページ")
    
    # 処理実行
    process_pages(pages)
    
    # 結果
    @end_time = Time.now
    result = build_result
    
    logger.info("=" * 60)
    logger.info(result.summary)
    logger.info("=" * 60)
    
    result
  rescue => e
    logger.error("致命的エラー: #{e.message}")
    logger.debug(e.backtrace.join("\n"))
    raise
  end
end

def build_result
  ArchiveResult.new(
    total_pages: @stats[:pages][:total],
    succeeded_pages: @stats[:pages][:succeeded],
    failed_pages: @stats[:pages][:failed],
    total_assets: @stats[:assets][:total],
    succeeded_assets: @stats[:assets][:succeeded],
    failed_assets: @stats[:assets][:failed],
    skipped_assets: @stats[:assets][:skipped],
    start_time: @start_time,
    end_time: @end_time || Time.now
  )
end
```

## 5. ログ設定

### 5.1 ログ設定

```ruby
def setup_logger
  log_dir = File.join(@output_dir, 'logs')
  FileUtils.mkdir_p(log_dir)
  
  log_file = File.join(log_dir, "wolf_archiver_#{Time.now.strftime('%Y%m%d_%H%M%S')}.log")
  
  @logger = Logger.new(log_file)
  @logger.level = ENV['DEBUG'] ? Logger::DEBUG : Logger::INFO
  @logger.formatter = proc do |severity, datetime, progname, msg|
    "[#{datetime.strftime('%Y-%m-%d %H:%M:%S')}] #{severity.ljust(5)} - #{msg}\n"
  end
  
  # 標準出力にも出力
  console_logger = Logger.new(STDOUT)
  console_logger.level = Logger::INFO
  console_logger.formatter = proc do |severity, datetime, progname, msg|
    case severity
    when 'ERROR'
      "\e[31m#{msg}\e[0m"  # 赤
    when 'WARN'
      "\e[33m#{msg}\e[0m"  # 黄
    when 'INFO'
      msg
    else
      "\e[90m#{msg}\e[0m"  # グレー
    end
  end
  
  # 両方に出力
  @multi_logger = MultiLogger.new(@logger, console_logger)
end

class MultiLogger
  def initialize(*loggers)
    @loggers = loggers
  end
  
  [:debug, :info, :warn, :error, :fatal].each do |level|
    define_method(level) do |message|
      @loggers.each { |logger| logger.send(level, message) }
    end
  end
end

def logger
  @multi_logger
end
```

## 6. ArchiveResult

### 6.1 結果クラス

```ruby
class ArchiveResult
  attr_reader :total_pages, :succeeded_pages, :failed_pages
  attr_reader :total_assets, :succeeded_assets, :failed_assets, :skipped_assets
  attr_reader :start_time, :end_time
  
  def initialize(total_pages:, succeeded_pages:, failed_pages:,
                 total_assets:, succeeded_assets:, failed_assets:, skipped_assets:,
                 start_time:, end_time:)
    @total_pages = total_pages
    @succeeded_pages = succeeded_pages
    @failed_pages = failed_pages
    @total_assets = total_assets
    @succeeded_assets = succeeded_assets
    @failed_assets = failed_assets
    @skipped_assets = skipped_assets
    @start_time = start_time
    @end_time = end_time
  end
  
  def duration
    @end_time - @start_time
  end
  
  def duration_str
    total_seconds = duration.to_i
    hours = total_seconds / 3600
    minutes = (total_seconds % 3600) / 60
    seconds = total_seconds % 60
    
    if hours > 0
      "#{hours}時間#{minutes}分#{seconds}秒"
    elsif minutes > 0
      "#{minutes}分#{seconds}秒"
    else
      "#{seconds}秒"
    end
  end
  
  def page_success_rate
    return 1.0 if total_pages == 0
    succeeded_pages.to_f / total_pages
  end
  
  def asset_success_rate
    return 1.0 if total_assets == 0
    succeeded_assets.to_f / (succeeded_assets + failed_assets)
  end
  
  def summary
    <<~SUMMARY
      アーカイブ完了
      
      実行時間: #{duration_str}
      
      ページ:
        合計: #{total_pages}件
        成功: #{succeeded_pages}件
        失敗: #{failed_pages}件
        成功率: #{(page_success_rate * 100).round(1)}%
      
      アセット:
        合計: #{total_assets}件
        成功: #{succeeded_assets}件
        失敗: #{failed_assets}件
        スキップ: #{skipped_assets}件
        成功率: #{(asset_success_rate * 100).round(1)}%
    SUMMARY
  end
end
```

## 7. エラーハンドリング

### 7.1 グローバルエラーハンドリング

```ruby
def run(options)
  begin
    # ... 処理 ...
  rescue ConfigError => e
    logger.error("設定エラー: #{e.message}")
    raise
  rescue Interrupt
    logger.warn("ユーザーによる中断")
    raise
  rescue => e
    logger.error("予期しないエラー: #{e.class} - #{e.message}")
    logger.debug(e.backtrace.join("\n"))
    raise
  end
end
```

### 7.2 リカバリー可能なエラー

```ruby
def process_single_page(page)
  # ...
rescue FetchError => e
  logger.error("ダウンロードエラー: #{e.message}")
  # スキップして次へ
rescue ParserError => e
  logger.error("解析エラー: #{e.message}")
  # スキップして次へ
rescue => e
  logger.error("ページ処理エラー: #{e.message}")
  raise  # 予期しないエラーは再raise
end
```

## 8. 使用例

### 8.1 基本的な使用

```bash
# サイト全体をアーカイブ
$ wolf_archiver fetch site_a

# 出力先を指定
$ wolf_archiver fetch site_a --output /path/to/archive

# 設定ファイルを指定
$ wolf_archiver fetch site_a --config my_sites.yml
```

### 8.2 特定の対象のみ

```bash
# 村のみ（ID指定）
$ wolf_archiver fetch site_a --village-ids 1 2 3

# ユーザーのみ（ID指定）
$ wolf_archiver fetch site_a --user-ids 100 101 102

# 静的ページのみ
$ wolf_archiver fetch site_a --static-only
```

### 8.3 自動検出

```bash
# 村を自動検出
$ wolf_archiver fetch site_a --auto-discover

# 村のみ自動検出
$ wolf_archiver fetch site_a --villages-only --auto-discover
```

### 8.4 その他

```bash
# サイト一覧
$ wolf_archiver list

# バージョン
$ wolf_archiver version

# ヘルプ
$ wolf_archiver help
$ wolf_archiver help fetch
```

## 9. テストケース

### 9.1 正常系

- [ ] 基本的なアーカイブ実行
- [ ] 村ID指定
- [ ] ユーザーID指定
- [ ] 自動検出
- [ ] 各オプションの組み合わせ
- [ ] 結果サマリーの出力

### 9.2 異常系

- [ ] 設定ファイルが存在しない
- [ ] 存在しないサイト名
- [ ] 不正な設定内容
- [ ] ダウンロード対象が0件
- [ ] すべてのページダウンロード失敗
- [ ] ユーザーによる中断（Ctrl+C）

### 9.3 エッジケース

- [ ] 非常に多数のページ（1000件以上）
- [ ] すでにアーカイブ済み（全スキップ）
- [ ] 部分的失敗（一部のページのみ成功）

## 10. 依存関係

すべてのモジュール：
- `ConfigLoader`
- `RateLimiter`
- `Fetcher`
- `Parser`
- `EncodingConverter`
- `Storage`
- `PathMapper`
- `LinkRewriter`
- `AssetDownloader`

外部Gem：
- `thor` (CLI)
- `tty-progressbar` (進捗表示)
- `logger` (標準ライブラリ)

## 11. 実装の注意点

### 11.1 メモリ管理

大量のページを処理する場合、ParseResultをすべてメモリに保持しない：

```ruby
# NG: メモリを大量消費
results = pages.map { |page| parse_and_process(page) }

# OK: 順次処理
pages.each { |page| parse_and_process(page) }
```

### 11.2 シグナルハンドリング

```ruby
trap('INT') do
  logger.warn("中断要求を受信しました...")
  # クリーンアップ処理
  exit 1
end
```

### 11.3 進捗表示の更新頻度

```ruby
# 頻繁に更新しすぎない
progressbar.advance  # ページごとに1回のみ

# アセットダウンロードでは個別に更新しない
# （AssetDownloaderが内部で管理）
```

### 11.4 設定の検証タイミング

```ruby
def initialize(site_name:, config_path:, output_dir:)
  # 早期に設定を検証
  @config_loader = ConfigLoader.new(config_path)  # ここでエラーが出る
  @site_config = @config_loader.site(site_name)    # ここでエラーが出る
  
  # 以降の処理は設定が正しいことが保証される
end
```

## 12. パフォーマンス最適化

### 12.1 スキップの早期判定

```ruby
def process_single_page(page)
  # 最初にスキップチェック（無駄なHTTPリクエストを防ぐ）
  if @storage.exist?(page[:path])
    logger.info("スキップ: #{page[:path]}")
    return
  end
  
  # ダウンロード処理
  # ...
end
```

### 12.2 バッチ処理

```ruby
# 2パスアプローチ（オプション）
def run_two_pass(pages)
  # パス1: すべてのページをダウンロード・解析してアセットを収集
  all_assets = []
  pages.each do |page|
    result = fetch_and_parse(page)
    all_assets.concat(result.assets)
  end
  
  # アセットを一括ダウンロード（重複除去済み）
  @asset_downloader.download(all_assets)
  
  # パス2: リンク書き換えと保存
  pages.each do |page|
    rewrite_and_save(page)
  end
end
```

**現状**: 1パスアプローチ（シンプル）で実装
**将来**: 2パスアプローチも選択可能に

### 12.3 キャッシュの活用

```ruby
# PathMapperのキャッシュ
@path_mapper = PathMapper.new(...)
# 内部でURLマッピング結果をキャッシュ

# LinkRewriterのキャッシュ
@link_rewriter = LinkRewriter.new(...)
# 内部で相対パス計算結果をキャッシュ
```

## 13. ロギング戦略

### 13.1 ログレベルの使い分け

```ruby
# DEBUG: 詳細な処理内容（デバッグ時のみ）
logger.debug("URLを解決: #{url} -> #{absolute_url}")

# INFO: 通常の処理進捗
logger.info("ページ処理開始: #{page[:path]}")

# WARN: 問題はあるが処理継続可能
logger.warn("アセットダウンロード失敗（スキップ）: #{asset.url}")

# ERROR: 個別の処理失敗（全体は継続）
logger.error("ページ処理エラー: #{page[:url]} - #{e.message}")

# FATAL: 致命的エラー（処理停止）
logger.fatal("設定ファイルが読み込めません")
```

### 13.2 ログファイルのローテーション

```ruby
def setup_logger
  log_file = File.join(log_dir, "wolf_archiver.log")
  
  # 日次ローテーション
  @logger = Logger.new(log_file, 'daily')
  
  # または、サイズローテーション
  # @logger = Logger.new(log_file, 10, 1024 * 1024)  # 10ファイル、各1MB
end
```

## 14. 設定例

### 14.1 完全な設定ファイル例

```yaml
# config/sites.yml
sites:
  sample_site:
    name: "サンプル人狼サイト"
    base_url: "http://example.com/wolf.cgi"
    encoding: "Shift_JIS"
    wait_time: 2.0
    
    assets:
      download: true
      types:
        - css
        - js
        - images
      css_dir: "assets/css"
      js_dir: "assets/js"
      images_dir: "assets/images"
    
    link_rewrite:
      enabled: true
      exclude_domains:
        - "twitter.com"
        - "facebook.com"
      fallback: "#"
    
    pages:
      index: "?cmd=top"
      village_list: "?cmd=vlist"
      village: "?cmd=vlog&vil=%{village_id}&turn=%{date}"
      user_list: "?cmd=ulist"
      user: "?cmd=ulog&uid=%{user_id}"
      static:
        - "?cmd=rule"
        - "?cmd=help"
        - "?cmd=guide"
    
    path_mapping:
      - pattern: '\?cmd=top'
        path: 'index.html'
      - pattern: '\?cmd=vlist'
        path: 'village_list.html'
      - pattern: '\?cmd=vlog&vil=(\d+)&turn=(\d+)'
        path: 'villages/%{1}/day%{2}.html'
      - pattern: '\?cmd=ulist'
        path: 'users/index.html'
      - pattern: '\?cmd=ulog&uid=(\d+)'
        path: 'users/%{1}.html'
      - pattern: '\?cmd=(\w+)'
        path: 'static/%{1}.html'
    
    # オプション: 村の最大日数
    villages:
      max_days: 10
  
  localhost_dev:
    name: "ローカル開発環境"
    base_url: "http://localhost:8080/wolf.cgi"
    encoding: "UTF-8"
    wait_time: 0  # localhost は待機なし
    
    # ... 同様の設定 ...
```

## 15. 統合テスト

### 15.1 エンドツーエンドテスト

```ruby
describe 'WolfArchiver Integration' do
  it 'サイト全体をアーカイブできる' do
    archiver = WolfArchiver.new(
      site_name: 'test_site',
      config_path: 'spec/fixtures/test_config.yml',
      output_dir: 'tmp/test_archive'
    )
    
    result = archiver.run(auto_discover: false, village_ids: [1, 2])
    
    expect(result.succeeded_pages).to be > 0
    expect(result.failed_pages).to eq(0)
    expect(File.exist?('tmp/test_archive/test_site/index.html')).to be true
    expect(File.exist?('tmp/test_archive/test_site/villages/1/day1.html')).to be true
  end
end
```

### 15.2 パフォーマンステスト

```ruby
describe 'WolfArchiver Performance' do
  it '100ページを5分以内に処理できる' do
    archiver = WolfArchiver.new(...)
    
    start_time = Time.now
    result = archiver.run(...)
    duration = Time.now - start_time
    
    expect(duration).to be < 300  # 5分
    expect(result.succeeded_pages).to eq(100)
  end
end
```

## 16. デプロイメント

### 16.1 実行可能ファイル

```ruby
#!/usr/bin/env ruby
# bin/wolf_archiver

require 'bundler/setup'
require_relative '../lib/wolf_archiver'

WolfArchiverCLI.start(ARGV)
```

### 16.2 Gemfile

```ruby
source 'https://rubygems.org'

gem 'nokogiri'
gem 'faraday'
gem 'addressable'
gem 'mime-types'
gem 'thor'
gem 'tty-progressbar'

group :development, :test do
  gem 'rspec'
  gem 'webmock'
  gem 'vcr'
end
```

### 16.3 インストール

```bash
# 開発モード
$ bundle install
$ chmod +x bin/wolf_archiver
$ ./bin/wolf_archiver version

# Gemとしてインストール（将来）
$ gem build wolf_archiver.gemspec
$ gem install wolf_archiver-1.0.0.gem
$ wolf_archiver version
```

## 17. ドキュメント

### 17.1 README.md

```markdown
# WolfArchiver

CGIベースの人狼ゲームサイトをアーカイブ化するCLIツール

## インストール

\`\`\`bash
bundle install
\`\`\`

## 使い方

\`\`\`bash
# 基本的な使用
wolf_archiver fetch site_a

# オプション指定
wolf_archiver fetch site_a --output ./archive --auto-discover

# ヘルプ
wolf_archiver help
\`\`\`

## 設定

`config/sites.yml` でサイトごとの設定を行います。

詳細は [CONFIGURATION.md](CONFIGURATION.md) を参照してください。

## ライセンス

MIT
```

### 17.2 CONFIGURATION.md

設定ファイルの詳細な説明を記載

### 17.3 DEVELOPMENT.md

開発者向けの情報（アーキテクチャ、テスト方法など）を記載

## 18. 今後の拡張

### 18.1 優先度: 高

- [ ] 並行ダウンロード対応（オプション）
- [ ] 差分アーカイブ（更新されたページのみ再取得）
- [ ] リトライ処理（一時的なエラーへの対応）
- [ ] より詳細な進捗表示（ETA表示）

### 18.2 優先度: 中

- [ ] 圧縮アーカイブ出力（zip/tar.gz）
- [ ] Webサーバー機能（ローカルでアーカイブを閲覧）
- [ ] 統計レポート生成（HTML形式）
- [ ] エクスポート形式の選択（HTML/Markdown/JSON）

### 18.3 優先度: 低

- [ ] GUI版の開発
- [ ] クラウドストレージへの自動アップロード
- [ ] スケジュール実行（cron連携）
- [ ] 通知機能（完了時にメール/Slack通知）

## 19. まとめ

WolfArchiverは以下の特徴を持つ統合アーカイブツールです：

### 主要機能
- ✅ CGIサイトの完全アーカイブ
- ✅ 文字エンコーディング自動変換
- ✅ 相対パスでのリンク書き換え
- ✅ アセット（CSS/JS/画像）の自動ダウンロード
- ✅ レート制限による負荷軽減
- ✅ 柔軟な対象選択（村/ユーザー/静的ページ）
- ✅ 自動検出機能

### 設計の特徴
- **モジュラー設計**: 各機能が独立したモジュール
- **責務分離**: 明確な役割分担
- **エラー耐性**: 部分的失敗でも処理継続
- **拡張性**: 新機能の追加が容易

### 技術スタック
- Ruby（標準ライブラリ中心）
- 最小限の外部依存（nokogiri, faraday, thor など）
- テスト可能な設計

これですべてのモジュールの詳細仕様が完成しました！