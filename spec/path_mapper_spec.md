# PathMapper 詳細仕様

## 1. 責務

URLをローカルファイルシステムのパスに変換する。
設定ファイル（`sites.yml`）で定義されたマッピングルールに基づき、動的URLを静的なファイルパスにマッピングする。
また、アセット（画像、CSS、JS）のURLを、ディレクトリ構造を維持したままローカルパスに変換する。

## 2. インターフェース

### 2.1 クラス定義

```ruby
class PathMapper
  # 初期化
  # @param base_url [String] サイトのベースURL
  # @param path_mapping [Array<Hash>] パスマッピングルールのリスト
  def initialize(base_url, path_mapping)

  # URLをローカルパスに変換
  # @param url [String] 変換対象のURL
  # @return [String, nil] ローカルパス（マッピングできない場合はnil）
  def url_to_path(url)
end
```

## 3. マッピングロジック

### 3.1 ページマッピング

`path_mapping` 設定に基づき、以下の優先順位でマッチングを行う。

1. **完全一致 (`exact`)**: URLが指定された文字列と完全に一致する場合。
2. **パラメータマッチ (`params`)**: URLのクエリパラメータが指定された条件と一致する場合。

#### 設定例 (`sites.yml`)

```yaml
path_mapping:
  # 完全一致
  - path: "index.html"
    exact: "?cmd=top"

  # パラメータマッチ
  - path: "villages/%{vid}/day%{turn}.html"
    params:
      cmd: "vlog"
      vid: "\\d+"
      turn: "\\d+"
```

#### プレースホルダー

パス内の `%{param_name}` は、対応するクエリパラメータの値に置換される。

### 3.2 アセットマッピング

アセット（画像、CSS、JS）のURLは、以下のルールでマッピングされる。

1. **拡張子の確認**: URLのパス部分が一般的なアセット拡張子（.css, .js, .png, .jpg, .gif, .ico, .svg, .woff, .ttf, .eot）で終わるか確認。
2. **ディレクトリ構造の維持**: URLのパス部分をそのままローカルの `assets/` ディレクトリ配下にマッピングする。
   - 例: `http://example.com/css/style.css` -> `assets/css/style.css`
   - 例: `http://example.com/img/icon.png` -> `assets/img/icon.png`
3. **クエリパラメータの除外**: アセットURLのクエリパラメータは無視される（ファイル名には含まれない）。

## 4. エラーハンドリング

- **マッピング不可**: 定義されたルールに一致せず、アセットでもないURLは `nil` を返す。
- **不正なURL**: パースできないURLが渡された場合は `nil` を返す（ログに警告を出力）。

## 5. 依存関係

- `Addressable::URI`: URLのパースに使用。

## 6. テストケース

### 6.1 正常系

- [ ] 完全一致ルールの適用
- [ ] パラメータマッチルールの適用（正規表現あり）
- [ ] プレースホルダーの置換
- [ ] アセットURLのマッピング（ディレクトリ構造維持）
- [ ] クエリパラメータ付きアセットURLの処理

### 6.2 異常系

- [ ] マッピングルールに一致しないURL -> nil
- [ ] 異なるドメインのURL -> nil
- [ ] 不正なURL文字列 -> nil
