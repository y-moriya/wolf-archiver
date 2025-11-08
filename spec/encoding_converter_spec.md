# EncodingConverter 詳細仕様

## 1. 責務

任意の文字エンコーディングからUTF-8への変換を行う。
変換できない文字は適切に処理し、エラーを記録する。

## 2. インターフェース

### 2.1 クラス定義

```ruby
class EncodingConverter
  # 文字列をUTF-8に変換
  # @param content [String] 変換対象の文字列（バイナリ）
  # @param from_encoding [String] 元のエンコーディング名（"Shift_JIS", "EUC-JP", "UTF-8"）
  # @return [String] UTF-8に変換された文字列
  # @raise [EncodingError] 変換に失敗した場合
  def self.to_utf8(content, from_encoding)
  
  # サポートされているエンコーディングのリスト
  # @return [Array<String>]
  def self.supported_encodings
end

class EncodingError < StandardError
  attr_reader :from_encoding, :invalid_byte_count
  
  def initialize(message, from_encoding: nil, invalid_byte_count: 0)
    @from_encoding = from_encoding
    @invalid_byte_count = invalid_byte_count
    super(message)
  end
end
```

## 3. サポートするエンコーディング

- `Shift_JIS` (Windows-31J / CP932も含む)
- `EUC-JP`
- `UTF-8`

## 4. 変換処理の詳細

### 4.1 基本的な変換フロー

```ruby
def self.to_utf8(content, from_encoding)
  # 1. エンコーディング名の正規化
  normalized_encoding = normalize_encoding(from_encoding)
  
  # 2. サポート確認
  validate_encoding(normalized_encoding)
  
  # 3. 既にUTF-8の場合は変換不要
  return content.dup.force_encoding('UTF-8') if normalized_encoding == 'UTF-8'
  
  # 4. エンコーディングを設定
  content.force_encoding(normalized_encoding)
  
  # 5. UTF-8へ変換（不正な文字は置換）
  content.encode('UTF-8', 
    invalid: :replace,    # 不正なバイト列を置換
    undef: :replace,      # 未定義文字を置換
    replace: '?'          # 置換文字
  )
rescue Encoding::InvalidByteSequenceError, Encoding::UndefinedConversionError => e
  raise EncodingError.new(
    "エンコーディング変換に失敗しました: #{e.message}",
    from_encoding: from_encoding
  )
end
```

### 4.2 エンコーディング名の正規化

大文字小文字、ハイフンの有無を吸収：

```ruby
def self.normalize_encoding(encoding)
  # 正規化マップ
  ENCODING_MAP = {
    'shift_jis' => 'Shift_JIS',
    'shiftjis' => 'Shift_JIS',
    'sjis' => 'Shift_JIS',
    'cp932' => 'Shift_JIS',
    'windows-31j' => 'Shift_JIS',
    'euc-jp' => 'EUC-JP',
    'eucjp' => 'EUC-JP',
    'utf-8' => 'UTF-8',
    'utf8' => 'UTF-8'
  }
  
  normalized = encoding.to_s.downcase.gsub(/[-_]/, '')
  ENCODING_MAP[normalized] || encoding
end
```

### 4.3 不正文字の処理方針

| 状況 | 処理 | 理由 |
|------|------|------|
| 不正なバイト列 | `?` に置換 | データ損失を最小限に |
| 未定義文字 | `?` に置換 | 変換不可文字を明示 |
| エンコーディング検出失敗 | エラー | 誤った変換を防ぐ |

## 5. エラーハンドリング

### 5.1 エラーケース

#### 未サポートのエンコーディング

```ruby
EncodingConverter.to_utf8(content, 'ISO-8859-1')
# => EncodingError: 未サポートのエンコーディング: ISO-8859-1
```

#### 変換失敗

```ruby
# 完全に不正なデータの場合
EncodingConverter.to_utf8("\xFF\xFE\x00\x00", 'Shift_JIS')
# => EncodingError: エンコーディング変換に失敗しました: ...
```

### 5.2 警告ケース

変換時に不正文字が置換された場合、ログに警告を出力（ただしエラーにはしない）：

```ruby
# Logger経由で警告
logger.warn("EncodingConverter: #{count}文字を '?' に置換しました (#{from_encoding} -> UTF-8)")
```

## 6. 使用例

### 6.1 基本的な使用

```ruby
# Shift_JISからUTF-8へ
sjis_content = File.binread('shift_jis.html')
utf8_content = EncodingConverter.to_utf8(sjis_content, 'Shift_JIS')

# EUC-JPからUTF-8へ
euc_content = File.binread('euc_jp.html')
utf8_content = EncodingConverter.to_utf8(euc_content, 'EUC-JP')

# UTF-8（変換不要）
utf8_content = File.binread('utf8.html')
utf8_content = EncodingConverter.to_utf8(utf8_content, 'UTF-8')
```

### 6.2 エラーハンドリング

```ruby
begin
  utf8_content = EncodingConverter.to_utf8(content, encoding)
rescue EncodingError => e
  logger.error("変換エラー: #{e.message}")
  logger.error("元のエンコーディング: #{e.from_encoding}")
  # 変換できない場合はスキップ
  return nil
end
```

### 6.3 サポート確認

```ruby
supported = EncodingConverter.supported_encodings
# => ["Shift_JIS", "EUC-JP", "UTF-8"]

if supported.include?(encoding)
  utf8_content = EncodingConverter.to_utf8(content, encoding)
end
```

## 7. 特殊ケースの処理

### 7.1 BOM（Byte Order Mark）

UTF-8のBOMは除去する：

```ruby
def self.remove_bom(content)
  # UTF-8 BOM: EF BB BF
  content.sub(/\A\xEF\xBB\xBF/n, '')
end
```

変換後に自動的にBOMを除去：

```ruby
def self.to_utf8(content, from_encoding)
  # ... 変換処理 ...
  result = content.encode('UTF-8', ...)
  remove_bom(result)
end
```

### 7.2 改行コードの統一

変換時に改行コードをLF（`\n`）に統一するオプションを提供：

```ruby
def self.to_utf8(content, from_encoding, normalize_newlines: true)
  result = # ... 変換処理 ...
  
  if normalize_newlines
    result.gsub(/\r\n|\r/, "\n")
  else
    result
  end
end
```

**デフォルト動作**: 改行コードをLFに統一（`normalize_newlines: true`）
**理由**: アーカイブの一貫性を保ち、Git管理時の差分を最小化

### 7.3 空文字列・nil

```ruby
# 空文字列
EncodingConverter.to_utf8('', 'Shift_JIS')
# => ''

# nil（エラー）
EncodingConverter.to_utf8(nil, 'Shift_JIS')
# => ArgumentError: content must be a String
```

## 8. パフォーマンス考慮

### 8.1 文字列のコピー

元の文字列を変更しないため、必要に応じてコピーを作成：

```ruby
content.dup.force_encoding(normalized_encoding)
```

### 8.2 大容量ファイル

メモリに一度に読み込むため、極端に大きなファイル（100MB以上）では注意が必要。
ただし、通常のHTMLファイルは数KB〜数MB程度なので問題なし。

## 9. ログ出力

### 9.1 ログレベル

| レベル | 内容 |
|--------|------|
| DEBUG | 変換開始・完了（エンコーディング名、サイズ） |
| WARN | 不正文字の置換が発生 |
| ERROR | 変換失敗 |

### 9.2 ログメッセージ例

```ruby
# DEBUG
"EncodingConverter: 変換開始 Shift_JIS -> UTF-8 (12345 bytes)"
"EncodingConverter: 変換完了 (12340 bytes)"

# WARN
"EncodingConverter: 3文字を '?' に置換しました (Shift_JIS -> UTF-8)"

# ERROR
"EncodingConverter: 変換失敗 - invalid byte sequence in Shift_JIS"
```

## 10. テストケース

### 10.1 正常系

- [ ] Shift_JIS → UTF-8 変換
- [ ] EUC-JP → UTF-8 変換
- [ ] UTF-8 → UTF-8（変換なし）
- [ ] BOMの除去
- [ ] 改行コードの統一（オプション有効時）
- [ ] 空文字列の処理
- [ ] エンコーディング名の正規化（大文字小文字、ハイフン）
- [ ] Windows-31J（CP932）の扱い
- [ ] 典型的な日本語文字（ひらがな、カタカナ、漢字）
- [ ] 特殊文字（①②③、㈱、など）
- [ ] 半角カナ

### 10.2 異常系

- [ ] 未サポートのエンコーディング → EncodingError
- [ ] nilを渡す → ArgumentError
- [ ] 完全に不正なバイト列 → EncodingError
- [ ] 部分的に不正なバイト列 → 警告 + `?` 置換

### 10.3 エッジケース

- [ ] 0バイトの文字列
- [ ] 不正文字が連続する場合
- [ ] UTF-8としてvalidだがShift_JISとして不正なデータ
- [ ] BOMが複数ある場合（最初のみ除去）
- [ ] 異なる改行コードが混在（CRLF, LF, CR）

## 11. 依存関係

なし（Ruby標準ライブラリのみ）

## 12. 実装の注意点

### 12.1 force_encodingとencode

- `force_encoding`: バイト列に対してエンコーディング情報を設定（変換なし）
- `encode`: 実際に文字列を変換

正しい順序：
```ruby
# 1. force_encodingで元のエンコーディングを設定
content.force_encoding('Shift_JIS')

# 2. encodeで変換
content.encode('UTF-8', invalid: :replace, undef: :replace)
```

### 12.2 エンコーディング検証

Rubyが認識できるエンコーディング名か確認：

```ruby
def self.validate_encoding(encoding)
  Encoding.find(encoding)
rescue ArgumentError
  raise EncodingError, "未サポートのエンコーディング: #{encoding}"
end
```

### 12.3 不変性

入力文字列を変更しない：

```ruby
# NG: 元の文字列を変更してしまう
content.force_encoding!('Shift_JIS')

# OK: コピーを作成
content.dup.force_encoding('Shift_JIS')
```

## 13. 今後の拡張可能性

- 自動エンコーディング検出（Shift_JIS/EUC-JPの判別）
- より多くのエンコーディング対応（ISO-2022-JP など）
- 統計情報の取得（置換文字数、変換前後のサイズ）
- ストリーミング変換（大容量ファイル対応）

## 14. 次のステップ

EncodingConverterの仕様が確定したら、次は **RateLimiter** に進みます。
