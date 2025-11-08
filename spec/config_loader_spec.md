# ConfigLoader 詳細仕様

## 1. 責務

設定ファイル（YAML）を読み込み、検証し、使いやすい形式で提供する。

## 2. インターフェース

### 2.1 クラス定義

```ruby
class ConfigLoader
  # 設定ファイルを読み込む
  # @param config_path [String] 設定ファイルのパス
  # @return [ConfigLoader]
  # @raise [ConfigError] 設定ファイルが存在しない、読み込めない、不正な場合
  def initialize(config_path)
  
  # 指定されたサイトの設定を取得
  # @param site_name [String] サイト名
  # @return [SiteConfig]
  # @raise [ConfigError] サイトが見つからない場合
  def site(site_name)
  
  # 全サイト名のリストを取得
  # @return [Array<String>]
  def site_names
end

class SiteConfig
  attr_reader :name, :base_url, :encoding, :wait_time
  attr_reader :assets, :link_rewrite, :pages, :path_mapping
  
  # localhost判定
  # @return [Boolean]
  def localhost?
  
  # 実際の待機時間を取得（localhostなら0）
  # @return [Float]
  def actual_wait_time
end
```

## 3. 設定ファイル構造

### 3.1 必須項目

```yaml
sites:
  site_name:  # サイト識別子（英数字とアンダースコアのみ）
    name: "表示名"
    base_url: "http://example.com/wolf.cgi"
    encoding: "Shift_JIS"  # または "EUC-JP", "UTF-8"
    wait_time: 2.0
```

### 3.2 オプション項目（デフォルト値あり）

```yaml
    # アセット設定（デフォルト：download=true）
    assets:
      download: true
      types:
        - css
        - js
        - images
      css_dir: "assets/css"
      js_dir: "assets/js"
      images_dir: "assets/images"
    
    # リンク書き換え設定（デフォルト：enabled=true）
    link_rewrite:
      enabled: true
      exclude_domains: []
      fallback: "#"
    
    # ページ定義（オプション：指定しない場合は空）
    pages:
      index: "?cmd=top"
      village_list: "?cmd=vlist"
      village: "?cmd=vlog&vil=%{village_id}&turn=%{date}"
      user_list: "?cmd=ulist"
      user: "?cmd=ulog&uid=%{user_id}"
      static:
        - "?cmd=rule"
        - "?cmd=help"
    
    # パスマッピング（オプション）
    path_mapping:
      - pattern: '\?cmd=top'
        path: 'index.html'
      - pattern: '\?cmd=vlog&vil=(\d+)&turn=(\d+)'
        path: 'villages/%{1}/%{2}.html'
```

## 4. デフォルト値

### 4.1 assets

```ruby
{
  download: true,
  types: ['css', 'js', 'images'],
  css_dir: 'assets/css',
  js_dir: 'assets/js',
  images_dir: 'assets/images'
}
```

### 4.2 link_rewrite

```ruby
{
  enabled: true,
  exclude_domains: [],
  fallback: '#'
}
```

### 4.3 pages

```ruby
{}  # 空のハッシュ
```

### 4.4 path_mapping

```ruby
[]  # 空の配列
```

## 5. バリデーションルール

### 5.1 必須項目チェック

以下の項目が存在しない場合はエラー：

- `sites` キー
- 各サイトの `name`
- 各サイトの `base_url`
- 各サイトの `encoding`
- 各サイトの `wait_time`

**エラーメッセージ例**：
```
ConfigError: 必須項目 'name' が site 'site_a' に設定されていません
```

### 5.2 データ型チェック

| 項目 | 期待する型 | エラー条件 |
|------|-----------|-----------|
| `name` | String | 文字列でない、空文字列 |
| `base_url` | String (URL) | 文字列でない、空文字列、URL形式でない |
| `encoding` | String | 文字列でない、許可リストにない |
| `wait_time` | Numeric | 数値でない、負の数 |
| `assets.download` | Boolean | true/false以外 |
| `assets.types` | Array | 配列でない |
| `assets.*_dir` | String | 文字列でない |
| `link_rewrite.enabled` | Boolean | true/false以外 |
| `link_rewrite.exclude_domains` | Array | 配列でない |
| `link_rewrite.fallback` | String | 文字列でない |
| `pages` | Hash | ハッシュでない |
| `path_mapping` | Array | 配列でない |

### 5.3 値の範囲チェック

#### encoding
許可される値：
- `"Shift_JIS"`
- `"EUC-JP"`
- `"UTF-8"`

それ以外はエラー。

**エラーメッセージ例**：
```
ConfigError: encoding 'ISO-8859-1' は未対応です。対応エンコーディング: Shift_JIS, EUC-JP, UTF-8
```

#### wait_time
- 0以上の数値
- 負の数はエラー

**エラーメッセージ例**：
```
ConfigError: wait_time は0以上の数値である必要があります（現在: -1.5）
```

#### base_url
- `http://` または `https://` で始まる
- ホスト名が含まれている

**エラーメッセージ例**：
```
ConfigError: base_url が不正な形式です: 'invalid-url'
```

#### assets.types
許可される値（配列の要素として）：
- `"css"`
- `"js"`
- `"images"`

それ以外が含まれている場合は警告（エラーにはしない）。

### 5.4 path_mapping のバリデーション

各要素は以下を持つ必要がある：
- `pattern` (String): 正規表現パターン
- `path` (String): ファイルパス（`%{数字}` プレースホルダー含む）

**正規表現の検証**：
```ruby
begin
  Regexp.new(pattern)
rescue RegexpError => e
  raise ConfigError, "不正な正規表現: #{pattern} - #{e.message}"
end
```

**パスプレースホルダーの検証**：
- `%{数字}` の数字がキャプチャグループの範囲内か確認
- 例：パターンに2つのキャプチャグループ `(\d+)` がある場合、`%{1}`, `%{2}` のみ有効

## 6. エラークラス

```ruby
class ConfigError < StandardError
  attr_reader :config_path, :site_name, :field
  
  def initialize(message, config_path: nil, site_name: nil, field: nil)
    @config_path = config_path
    @site_name = site_name
    @field = field
    super(message)
  end
end
```

## 7. 使用例

### 7.1 基本的な使用

```ruby
# 設定読み込み
loader = ConfigLoader.new('config/sites.yml')

# サイト設定取得
site_config = loader.site('site_a')

puts site_config.name         # => "人狼サイトA"
puts site_config.base_url     # => "http://example.com/wolf.cgi"
puts site_config.encoding     # => "Shift_JIS"
puts site_config.wait_time    # => 2.0
puts site_config.localhost?   # => false
puts site_config.actual_wait_time  # => 2.0 (localhostなら0)

# アセット設定
puts site_config.assets[:download]  # => true
puts site_config.assets[:css_dir]   # => "assets/css"

# リンク書き換え設定
puts site_config.link_rewrite[:enabled]    # => true
puts site_config.link_rewrite[:fallback]   # => "#"

# ページ定義
puts site_config.pages[:index]  # => "?cmd=top"

# パスマッピング
site_config.path_mapping.each do |mapping|
  puts "#{mapping[:pattern]} => #{mapping[:path]}"
end
```

### 7.2 エラーハンドリング

```ruby
begin
  loader = ConfigLoader.new('config/sites.yml')
  site_config = loader.site('non_existent_site')
rescue ConfigError => e
  puts "設定エラー: #{e.message}"
  puts "設定ファイル: #{e.config_path}" if e.config_path
  puts "サイト名: #{e.site_name}" if e.site_name
  puts "フィールド: #{e.field}" if e.field
  exit 1
end
```

## 8. 実装の注意点

### 8.1 localhost判定

```ruby
def localhost?
  uri = URI.parse(@base_url)
  ['localhost', '127.0.0.1', '::1'].include?(uri.host)
rescue URI::InvalidURIError
  false
end
```

### 8.2 actual_wait_time

```ruby
def actual_wait_time
  localhost? ? 0 : @wait_time
end
```

### 8.3 設定のディープマージ

デフォルト値とユーザー設定をマージする際は、ネストしたハッシュも適切にマージする。

```ruby
# 浅いマージ（NG）
default.merge(user_config)

# 深いマージ（OK）
deep_merge(default, user_config)
```

### 8.4 不変性

設定オブジェクトは読み取り専用とする（フリーズ推奨）。

```ruby
@config.freeze
```

## 9. テストケース

### 9.1 正常系

- [ ] 最小限の設定で読み込める
- [ ] 全項目を指定した設定で読み込める
- [ ] デフォルト値が正しく適用される
- [ ] localhost判定が正しく動作する
- [ ] actual_wait_timeがlocalhostで0になる
- [ ] 複数サイトの設定を読み込める
- [ ] 日本語のサイト名が扱える

### 9.2 異常系

- [ ] 設定ファイルが存在しない → ConfigError
- [ ] YAMLパースエラー → ConfigError
- [ ] 必須項目が欠落 → ConfigError
- [ ] encodingが未対応 → ConfigError
- [ ] wait_timeが負の数 → ConfigError
- [ ] base_urlが不正な形式 → ConfigError
- [ ] 存在しないサイト名を指定 → ConfigError
- [ ] path_mappingの正規表現が不正 → ConfigError
- [ ] sitesキーが存在しない → ConfigError
- [ ] データ型が不正 → ConfigError

## 10. 依存関係

- `yaml` (標準ライブラリ)
- `uri` (標準ライブラリ)

## 11. 次のステップ

ConfigLoaderの仕様が確定したら、次は以下のモジュールに進みます：

1. **EncodingConverter** - 文字コード変換
2. **RateLimiter** - アクセス間隔制御

どちらから詳細化しますか？
