# Storage 詳細仕様

## 1. 責務

ファイルシステムへのデータ保存を管理する。
ディレクトリ構造の作成、ファイルの書き込み、重複チェックを行う。

## 2. インターフェース

### 2.1 クラス定義

```ruby
class Storage
  # 初期化
  # @param base_dir [String] ベースディレクトリ（例: "archive/site_a"）
  def initialize(base_dir)
  
  # ファイルを保存
  # @param relative_path [String] ベースディレクトリからの相対パス
  # @param content [String] 保存する内容
  # @param encoding [String] ファイルのエンコーディング（デフォルト: 'UTF-8'）
  # @return [String] 保存したファイルの絶対パス
  # @raise [StorageError] 保存失敗時
  def save(relative_path, content, encoding: 'UTF-8')
  
  # バイナリファイルを保存
  # @param relative_path [String] ベースディレクトリからの相対パス
  # @param content [String] バイナリデータ
  # @return [String] 保存したファイルの絶対パス
  # @raise [StorageError] 保存失敗時
  def save_binary(relative_path, content)
  
  # ファイルが存在するか確認
  # @param relative_path [String] ベースディレクトリからの相対パス
  # @return [Boolean]
  def exist?(relative_path)
  
  # ファイルを読み込み
  # @param relative_path [String] ベースディレクトリからの相対パス
  # @param encoding [String] ファイルのエンコーディング（デフォルト: 'UTF-8'）
  # @return [String, nil] ファイルの内容（存在しない場合はnil）
  def read(relative_path, encoding: 'UTF-8')
  
  # 絶対パスを取得
  # @param relative_path [String] ベースディレクトリからの相対パス
  # @return [String] 絶対パス
  def absolute_path(relative_path)
  
  # ディレクトリを削除（テスト用）
  # @return [void]
  def clear
end

class StorageError < StandardError
  attr_reader :path, :original_error
  
  def initialize(message, path: nil, original_error: nil)
    @path = path
    @original_error = original_error
    super(message)
  end
end
```

## 3. ディレクトリ構造

### 3.1 基本構造

```
archive/
└── site_a/                    # base_dir
    ├── index.html
    ├── village_list.html
    ├── villages/
    │   ├── 1/
    │   │   ├── day1.html
    │   │   └── day2.html
    │   └── 2/
    │       └── day1.html
    ├── users/
    │   ├── index.html
    │   ├── 1.html
    │   └── 2.html
    ├── static/
    │   ├── rule.html
    │   └── help.html
    └── assets/
        ├── css/
        │   └── style.css
        ├── js/
        │   └── script.js
        └── images/
            ├── icon.png
            └── bg.jpg
```

### 3.2 パス正規化

```ruby
def normalize_path(relative_path)
  # 先頭のスラッシュを除去
  path = relative_path.sub(/\A\/+/, '')
  
  # 連続するスラッシュを単一に
  path = path.gsub(/\/+/, '/')
  
  # パストラバーサル攻撃を防ぐ
  if path.include?('..')
    raise StorageError.new("不正なパス: #{relative_path}")
  end
  
  path
end
```

## 4. 保存処理の詳細

### 4.1 テキストファイル保存

```ruby
def save(relative_path, content, encoding: 'UTF-8')
  path = normalize_path(relative_path)
  full_path = File.join(@base_dir, path)
  
  # ディレクトリを作成
  dir = File.dirname(full_path)
  FileUtils.mkdir_p(dir) unless Dir.exist?(dir)
  
  # ファイルを書き込み
  File.write(full_path, content, encoding: encoding)
  
  logger.info("Storage: 保存完了 #{path} (#{content.bytesize} bytes)")
  full_path
rescue Errno::EACCES => e
  raise StorageError.new("書き込み権限がありません: #{path}", path: path, original_error: e)
rescue Errno::ENOSPC => e
  raise StorageError.new("ディスク容量が不足しています: #{path}", path: path, original_error: e)
rescue => e
  raise StorageError.new("保存失敗: #{e.message}", path: path, original_error: e)
end
```

### 4.2 バイナリファイル保存

```ruby
def save_binary(relative_path, content)
  path = normalize_path(relative_path)
  full_path = File.join(@base_dir, path)
  
  # ディレクトリを作成
  dir = File.dirname(full_path)
  FileUtils.mkdir_p(dir) unless Dir.exist?(dir)
  
  # バイナリモードで書き込み
  File.binwrite(full_path, content)
  
  logger.info("Storage: バイナリ保存完了 #{path} (#{content.bytesize} bytes)")
  full_path
rescue => e
  raise StorageError.new("バイナリ保存失敗: #{e.message}", path: path, original_error: e)
end
```

### 4.3 ディレクトリ作成

```ruby
def ensure_directory(path)
  dir = File.dirname(path)
  return if Dir.exist?(dir)
  
  FileUtils.mkdir_p(dir)
  logger.debug("Storage: ディレクトリ作成 #{dir}")
rescue => e
  raise StorageError.new("ディレクトリ作成失敗: #{e.message}", path: dir, original_error: e)
end
```

## 5. 重複チェック

### 5.1 存在確認

```ruby
def exist?(relative_path)
  path = normalize_path(relative_path)
  full_path = File.join(@base_dir, path)
  File.exist?(full_path)
end
```

### 5.2 スキップロジックとの連携

```ruby
# メインループでの使用例
urls.each do |url, relative_path|
  if storage.exist?(relative_path)
    logger.info("スキップ: #{relative_path} (既に存在)")
    next
  end
  
  # ダウンロード処理
  result = fetcher.fetch(url)
  storage.save(relative_path, result.body)
end
```

## 6. 読み込み処理

### 6.1 テキストファイル読み込み

```ruby
def read(relative_path, encoding: 'UTF-8')
  path = normalize_path(relative_path)
  full_path = File.join(@base_dir, path)
  
  return nil unless File.exist?(full_path)
  
  File.read(full_path, encoding: encoding)
rescue => e
  logger.error("Storage: 読み込み失敗 #{path} - #{e.message}")
  nil
end
```

### 6.2 バイナリファイル読み込み

```ruby
def read_binary(relative_path)
  path = normalize_path(relative_path)
  full_path = File.join(@base_dir, path)
  
  return nil unless File.exist?(full_path)
  
  File.binread(full_path)
rescue => e
  logger.error("Storage: バイナリ読み込み失敗 #{path} - #{e.message}")
  nil
end
```

## 7. ファイル名のサニタイズ

### 7.1 禁止文字の除去

```ruby
def sanitize_filename(filename)
  # Windowsで使えない文字を除去
  sanitized = filename.gsub(/[<>:"\/\\|?*]/, '_')
  
  # 制御文字を除去
  sanitized = sanitized.gsub(/[\x00-\x1F\x7F]/, '')
  
  # 先頭・末尾の空白とドットを除去
  sanitized = sanitized.strip.gsub(/\A\.+|\.+\z/, '')
  
  # 空になった場合はデフォルト名
  sanitized.empty? ? 'unnamed' : sanitized
end
```

### 7.2 パスコンポーネントのサニタイズ

```ruby
def sanitize_path(path)
  path.split('/').map { |component| sanitize_filename(component) }.join('/')
end
```

## 8. エラーハンドリング

### 8.1 エラー種別

| エラー | 原因 | 処理 |
|--------|------|------|
| `Errno::EACCES` | 書き込み権限なし | StorageError |
| `Errno::ENOSPC` | ディスク容量不足 | StorageError |
| `Errno::ENAMETOOLONG` | ファイル名が長すぎる | StorageError |
| `Errno::ENOENT` | 親ディレクトリが存在しない | ディレクトリ作成後リトライ |
| パストラバーサル | `..` を含むパス | StorageError |

### 8.2 エラーメッセージ

```ruby
# 書き込み権限エラー
"書き込み権限がありません: villages/1/day1.html"

# ディスク容量不足
"ディスク容量が不足しています: villages/1/day1.html"

# 不正なパス
"不正なパス: ../../../etc/passwd"

# ファイル名が長すぎる
"ファイル名が長すぎます: very_long_filename_..."
```

## 9. ログ出力

### 9.1 ログレベル

| レベル | 内容 |
|--------|------|
| DEBUG | ディレクトリ作成、パス正規化 |
| INFO | ファイル保存完了、サイズ |
| WARN | スキップ（既存ファイル） |
| ERROR | 保存失敗 |

### 9.2 ログメッセージ例

```ruby
# DEBUG
"Storage: ディレクトリ作成 archive/site_a/villages/1"
"Storage: パス正規化 /villages/1/day1.html -> villages/1/day1.html"

# INFO
"Storage: 保存完了 villages/1/day1.html (12345 bytes)"
"Storage: バイナリ保存完了 assets/images/icon.png (8192 bytes)"

# WARN
"Storage: スキップ villages/1/day1.html (既に存在)"

# ERROR
"Storage: 保存失敗 villages/1/day1.html - Permission denied"
```

## 10. 使用例

### 10.1 基本的な使用

```ruby
storage = Storage.new('archive/site_a')

# HTMLファイルを保存
html_content = "<html>...</html>"
storage.save('index.html', html_content)

# ディレクトリを含むパスで保存
storage.save('villages/1/day1.html', html_content)

# バイナリファイルを保存
image_data = File.binread('icon.png')
storage.save_binary('assets/images/icon.png', image_data)

# 存在確認
if storage.exist?('index.html')
  puts "index.htmlは既に存在します"
end

# 読み込み
content = storage.read('index.html')
```

### 10.2 エラーハンドリング

```ruby
begin
  storage.save('villages/1/day1.html', html_content)
rescue StorageError => e
  logger.error("保存エラー: #{e.message}")
  logger.error("パス: #{e.path}")
  logger.error("原因: #{e.original_error.class}") if e.original_error
end
```

### 10.3 重複スキップ

```ruby
pages = [
  { path: 'index.html', url: '?cmd=top' },
  { path: 'villages/1/day1.html', url: '?cmd=vlog&vil=1&turn=1' }
]

pages.each do |page|
  if storage.exist?(page[:path])
    logger.info("スキップ: #{page[:path]}")
    next
  end
  
  result = fetcher.fetch(page[:url])
  content = EncodingConverter.to_utf8(result.body, 'Shift_JIS')
  storage.save(page[:path], content)
end
```

## 11. パフォーマンス考慮

### 11.1 ディレクトリキャッシュ

頻繁にディレクトリ存在チェックをしないよう、作成済みディレクトリをキャッシュ：

```ruby
def initialize(base_dir)
  @base_dir = base_dir
  @created_dirs = Set.new
end

def ensure_directory(path)
  dir = File.dirname(path)
  return if @created_dirs.include?(dir)
  
  FileUtils.mkdir_p(dir) unless Dir.exist?(dir)
  @created_dirs.add(dir)
end
```

### 11.2 バッファリング

大容量ファイルの場合、一度にメモリに読み込まない：

```ruby
# 現時点では不要（HTMLは通常数KB〜数MB）
# 将来的に大容量対応する場合：
def save_stream(relative_path, io)
  full_path = absolute_path(relative_path)
  ensure_directory(full_path)
  
  File.open(full_path, 'wb') do |file|
    IO.copy_stream(io, file)
  end
end
```

## 12. テストケース

### 12.1 正常系

- [ ] 通常のファイル保存
- [ ] ネストしたディレクトリでのファイル保存
- [ ] バイナリファイル保存
- [ ] 既存ファイルの上書き
- [ ] 存在確認（存在する/しない）
- [ ] ファイル読み込み
- [ ] 絶対パスの取得
- [ ] 日本語ファイル名

### 12.2 異常系

- [ ] 書き込み権限なし → StorageError
- [ ] ディスク容量不足 → StorageError
- [ ] 不正なパス（`..`含む） → StorageError
- [ ] 存在しないファイルの読み込み → nil
- [ ] 空文字列のパス → StorageError

### 12.3 パス正規化

- [ ] 先頭のスラッシュを除去
- [ ] 連続するスラッシュを単一に
- [ ] パストラバーサル攻撃を防ぐ
- [ ] Windowsの禁止文字をサニタイズ

### 12.4 エッジケース

- [ ] 非常に長いファイル名（255文字以上）
- [ ] 空のコンテンツ
- [ ] 巨大ファイル（100MB以上）
- [ ] 同時書き込み（競合）

## 13. 依存関係

- `fileutils` (標準ライブラリ)
- `pathname` (標準ライブラリ)
- `set` (標準ライブラリ)

## 14. 実装の注意点

### 14.1 相対パスと絶対パス

```ruby
# 相対パス：base_dirからの相対
storage.save('villages/1/day1.html', content)

# 絶対パス：内部で構築
full_path = File.join(@base_dir, 'villages/1/day1.html')
```

### 14.2 エンコーディング指定

```ruby
# UTF-8で保存（デフォルト）
storage.save('index.html', content)

# 別のエンコーディングで保存（通常は不要）
storage.save('legacy.html', content, encoding: 'Shift_JIS')
```

### 14.3 アトミック性

ファイル書き込みは一時ファイルを使用してアトミックに：

```ruby
def save_atomic(relative_path, content, encoding: 'UTF-8')
  full_path = absolute_path(relative_path)
  temp_path = "#{full_path}.tmp"
  
  # 一時ファイルに書き込み
  File.write(temp_path, content, encoding: encoding)
  
  # 一時ファイルをリネーム（アトミック）
  File.rename(temp_path, full_path)
ensure
  # 一時ファイルが残っている場合は削除
  File.delete(temp_path) if File.exist?(temp_path)
end
```

**現時点では不要**（単一プロセスで順次処理）

## 15. セキュリティ考慮

### 15.1 パストラバーサル対策

```ruby
# NG: 攻撃される可能性
storage.save('../../../etc/passwd', 'hacked')

# OK: 検証でエラー
def normalize_path(path)
  raise StorageError.new("不正なパス") if path.include?('..')
  # ...
end
```

### 15.2 シンボリックリンク

```ruby
# シンボリックリンクを辿らない
def exist?(relative_path)
  full_path = absolute_path(relative_path)
  File.exist?(full_path) && !File.symlink?(full_path)
end
```

**現時点では不要**（自分で作成するファイルのみ）

## 16. 今後の拡張可能性

- ストリーミング保存（大容量ファイル対応）
- 圧縮保存（gzip圧縮）
- メタデータ管理（保存日時、元URL）
- アトミック保存（一時ファイル使用）
- ファイルロック（並行処理対応）
- データベース連携（SQLite）

## 17. 次のステップ

Storageの仕様が確定したら、次は **Parser** に進みます。
Parserは最も複雑なモジュールで、HTML解析とリンク/アセット抽出を担当します。
