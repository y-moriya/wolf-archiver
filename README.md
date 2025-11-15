# README - WolfArchiver

CGIベースの人狼ゲームサイトをアーカイブ化するコマンドラインツール

## 概要

WolfArchiverは、レガシーなCGIベースの人狼ゲームサイトを、完全にオフライン閲覧可能なHTMLアーカイブに変換します。

### 主な機能

- ✅ サイト全体の自動ダウンロード
- ✅ HTMLの文字エンコーディング自動変換（Shift_JIS, EUC-JP, UTF-8対応）
- ✅ CSS/JavaScript/画像などのアセット自動ダウンロード
- ✅ リンクの自動書き換え（相対パス化）
- ✅ サーバーへの負荷軽減（レート制限）
- ✅ 部分失敗の許容（一部エラーでも処理継続）
- ✅ 柔軟な対象選択（全ページ/村のみ/ユーザーのみ/静的ページのみ）
- ✅ 自動検出機能（一覧ページから自動取得）

## インストール

### 前提条件

- Ruby 3.2.0以上

### セットアップ

```bash
# 依存パッケージのインストール
bundle install

# 実行可能ファイルの準備
chmod +x bin/wolf_archiver
```

## 使い方

### 基本的な使用

```bash
# サイト全体をアーカイブ
./bin/wolf_archiver fetch sample_site

# 出力先を指定
./bin/wolf_archiver fetch sample_site --output /path/to/archive

# 設定ファイルを指定
./bin/wolf_archiver fetch sample_site --config my_config.yml
```

### 特定の対象のみ

```bash
# 村IDを指定してダウンロード
./bin/wolf_archiver fetch sample_site --village-ids 1 2 3

# ユーザーIDを指定してダウンロード
./bin/wolf_archiver fetch sample_site --user-ids 100 101 102

# 村のみダウンロード
./bin/wolf_archiver fetch sample_site --villages-only

# ユーザーのみダウンロード
./bin/wolf_archiver fetch sample_site --users-only

# 静的ページのみダウンロード
./bin/wolf_archiver fetch sample_site --static-only
```

### 自動検出

```bash
# 一覧ページから対象を自動検出
./bin/wolf_archiver fetch sample_site --auto-discover

# 村のみ自動検出
./bin/wolf_archiver fetch sample_site --villages-only --auto-discover
```

### その他のコマンド

```bash
# 設定されているサイトの一覧
./bin/wolf_archiver list

# バージョン表示
./bin/wolf_archiver version

# ヘルプ表示
./bin/wolf_archiver help
./bin/wolf_archiver help fetch
```

## 設定

### 設定ファイル（config/sites.yml）

```yaml
sites:
  site_name:
    name: "表示名"
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
      exclude_domains: []
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
    
    path_mapping:
      - pattern: '\?cmd=top'
        path: 'index.html'
      - pattern: '\?cmd=vlog&vil=(\d+)&turn=(\d+)'
        path: 'villages/%{1}/day%{2}.html'
```

詳細な設定オプションについては、[仕様書](spec/config_loader_spec.md)を参照してください。

## ファイル構造

```
wolf-archiver/
├── bin/
│   └── wolf_archiver           # 実行可能ファイル
├── lib/
│   └── wolf_archiver/
│       ├── config_loader.rb    # 設定ファイル読み込み
│       ├── encoding_converter.rb # 文字エンコーディング変換
│       ├── rate_limiter.rb     # リクエスト間隔制限
│       ├── fetcher.rb          # HTTP通信
│       ├── parser.rb           # HTML解析
│       ├── storage.rb          # ファイルシステム管理
│       ├── path_mapper.rb      # URLからパスへのマッピング
│       ├── link_rewriter.rb    # リンク書き換え
│       ├── asset_downloader.rb # アセットダウンロード
│       ├── wolf_archiver.rb    # メインクラス
│       └── cli.rb              # CLIインターフェース
├── config/
│   └── sites.yml               # サイト設定
├── spec/
│   └── *.md                    # 仕様書
└── Gemfile
```

## 処理フロー

```
1. CLI引数の解析
2. 設定ファイル読み込み
3. 各モジュールの初期化
4. ダウンロード対象ページの決定
5. ページごとの処理：
   a. HTMLダウンロード
   b. エンコーディング変換（Shift_JIS/EUC-JP → UTF-8）
   c. HTML解析（リンク・アセット抽出）
   d. アセットダウンロード（CSS/JS/画像）
   e. リンク書き換え（絶対URL → 相対パス）
   f. ファイル保存
6. 結果サマリー表示
```

## 仕様書

各モジュールの詳細な仕様は `spec/` ディレクトリを参照：

- [config_loader_spec.md](spec/config_loader_spec.md) - 設定読み込み
- [encoding_converter_spec.md](spec/encoding_converter_spec.md) - 文字エンコーディング
- [rate_limiter_spec.md](spec/rate_limiter_spec.md) - レート制限
- [fetcher_spec.md](spec/fetcher_spec.md) - HTTP通信
- [parser_spec.md](spec/parser_spec.md) - HTML解析
- [storage_spec.md](spec/storage_spec.md) - ファイル管理
- [link_rewriter_spec.md](spec/link_rewriter_spec.md) - リンク書き換え
- [asset_downloader_spec.md](spec/asset_downloader_spec.md) - アセットダウンロード
- [wolf_archiver_spec.md](spec/wolf_archiver_spec.md) - メインクラス

## トラブルシューティング

### "設定ファイルが見つかりません" エラー

```bash
# 設定ファイルのパスを確認
ls -la config/sites.yml

# 設定ファイルのパスを指定
./bin/wolf_archiver fetch sample_site --config /path/to/sites.yml
```

### 文字化け

設定ファイルで正しいエンコーディングを指定してください：

```yaml
encoding: "Shift_JIS"  # または "EUC-JP", "UTF-8"
```

### ダウンロードが遅い

`wait_time` を小さくしてください（ただし、サーバーに負荷をかけすぎないよう注意）：

```yaml
wait_time: 0.5  # 500ms の待機時間
```

## 開発

### テスト実行

```bash
bundle exec rspec
```

### ドキュメント生成

```bash
yard doc
```

## ライセンス

MIT

## 作者

wellk

## 更新履歴

### v1.0.0 (2025-11-15)

- 初版リリース
- 基本的なアーカイブ機能完成
- すべてのモジュール実装完了
