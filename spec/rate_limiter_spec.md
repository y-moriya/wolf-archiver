# RateLimiter 詳細仕様

## 1. 責務

リクエスト間隔を制御し、サーバーへの負荷を軽減する。
指定された待機時間を管理し、適切なタイミングでリクエストを許可する。

## 2. インターフェース

### 2.1 クラス定義

```ruby
class RateLimiter
  # 初期化
  # @param wait_time [Float] 待機時間（秒）
  # @param enabled [Boolean] レート制限を有効にするか
  def initialize(wait_time, enabled: true)
  
  # リクエスト実行を待機
  # 前回のリクエストから wait_time 経過していない場合は待機する
  # @return [void]
  def wait
  
  # 前回のリクエストからの経過時間
  # @return [Float] 経過秒数（初回は無限大）
  def elapsed_time
  
  # 次のリクエストまでの残り待機時間
  # @return [Float] 残り秒数（待機不要なら0）
  def remaining_wait_time
  
  # レート制限が有効か
  # @return [Boolean]
  def enabled?
  
  # リセット（テスト用）
  # @return [void]
  def reset
end
```

## 3. 動作仕様

### 3.1 基本動作

```ruby
limiter = RateLimiter.new(2.0)  # 2秒間隔

# 1回目のリクエスト（即座に実行）
limiter.wait  # 待機なし
make_request()

# 2回目のリクエスト（1秒後）
limiter.wait  # 残り1秒待機
make_request()

# 3回目のリクエスト（2秒経過後）
limiter.wait  # 待機なし
make_request()
```

### 3.2 待機時間の計算

```ruby
def wait
  return unless @enabled
  return if @last_request_time.nil?  # 初回は待機なし
  
  elapsed = Time.now - @last_request_time
  remaining = @wait_time - elapsed
  
  if remaining > 0
    logger.debug("RateLimiter: #{remaining.round(2)}秒待機中...")
    sleep(remaining)
  end
  
  @last_request_time = Time.now
end
```

### 3.3 無効化モード

```ruby
limiter = RateLimiter.new(2.0, enabled: false)
limiter.wait  # 何もしない（即座にリターン）
```

**用途**: テスト時やlocalhostアクセス時

## 4. 初期化パターン

### 4.1 通常サイト

```ruby
# 2秒間隔で待機
limiter = RateLimiter.new(2.0)
```

### 4.2 localhost（待機なし）

```ruby
# wait_timeが0の場合は自動的に無効化
limiter = RateLimiter.new(0)
# または明示的に無効化
limiter = RateLimiter.new(2.0, enabled: false)
```

### 4.3 ConfigLoaderとの連携

```ruby
site_config = config_loader.site('site_a')

# localhostの場合は自動的に待機なし
if site_config.localhost?
  limiter = RateLimiter.new(0, enabled: false)
else
  limiter = RateLimiter.new(site_config.wait_time)
end

# または
limiter = RateLimiter.new(
  site_config.actual_wait_time,
  enabled: !site_config.localhost?
)
```

## 5. ログ出力

### 5.1 ログレベル

| レベル | 内容 |
|--------|------|
| DEBUG | 待機開始・待機時間 |
| INFO | レート制限の有効/無効状態 |

### 5.2 ログメッセージ例

```ruby
# DEBUG
"RateLimiter: 1.50秒待機中..."
"RateLimiter: 待機完了"

# INFO（初期化時）
"RateLimiter: 初期化完了 (wait_time: 2.0s, enabled: true)"
"RateLimiter: レート制限無効（localhost）"
```

## 6. 使用例

### 6.1 基本的な使用

```ruby
limiter = RateLimiter.new(2.0)

urls = [
  'http://example.com/page1',
  'http://example.com/page2',
  'http://example.com/page3'
]

urls.each do |url|
  limiter.wait  # 必要に応じて待機
  response = fetch(url)
  process(response)
end
```

### 6.2 進捗表示との連携

```ruby
limiter = RateLimiter.new(2.0)
progressbar = TTY::ProgressBar.new("[:bar] :current/:total", total: urls.size)

urls.each do |url|
  remaining = limiter.remaining_wait_time
  if remaining > 0
    progressbar.log("#{remaining.round(1)}秒待機中...")
  end
  
  limiter.wait
  fetch(url)
  progressbar.advance
end
```

### 6.3 条件付き無効化

```ruby
# テスト環境では待機なし
limiter = RateLimiter.new(
  wait_time,
  enabled: ENV['RAILS_ENV'] != 'test'
)
```

## 7. エッジケース

### 7.1 wait_time = 0

```ruby
limiter = RateLimiter.new(0)
limiter.wait  # 即座にリターン（待機なし）
```

### 7.2 wait_timeが非常に小さい（< 0.1秒）

```ruby
limiter = RateLimiter.new(0.05)
limiter.wait  # 正確に50ms待機
```

精度は`sleep`の精度に依存（通常は10ms程度の誤差）。

### 7.3 システム時刻の変更

システム時刻が変更された場合：

```ruby
# Time.nowの代わりにProcess.clock_gettimeを使用
def current_time
  Process.clock_gettime(Process::CLOCK_MONOTONIC)
end
```

**CLOCK_MONOTONIC**: システム時刻の変更の影響を受けない単調増加時計

### 7.4 負の待機時間

十分に時間が経過している場合、remainingが負になる可能性：

```ruby
remaining = @wait_time - elapsed  # 例: 2.0 - 5.0 = -3.0

if remaining > 0
  sleep(remaining)
end
# 負の場合はsleepしない
```

## 8. スレッドセーフティ

現状の仕様では**スレッドセーフではない**（並行アクセスしないため不要）。

将来的に並行処理を追加する場合はMutexが必要：

```ruby
class RateLimiter
  def initialize(wait_time, enabled: true)
    @wait_time = wait_time
    @enabled = enabled
    @last_request_time = nil
    @mutex = Mutex.new  # 追加
  end
  
  def wait
    @mutex.synchronize do
      # ... 待機処理 ...
    end
  end
end
```

**現時点では実装不要**

## 9. テストケース

### 9.1 正常系

- [ ] 初回リクエストは待機なし
- [ ] 2回目のリクエストは適切に待機
- [ ] 十分な時間が経過していれば待機なし
- [ ] wait_time = 0 の場合は常に待機なし
- [ ] enabled: false の場合は常に待機なし
- [ ] elapsed_timeが正しく計算される
- [ ] remaining_wait_timeが正しく計算される

### 9.2 タイミング精度

- [ ] 待機時間の誤差が±100ms以内
- [ ] 連続リクエスト時の間隔が wait_time ± 100ms 以内

### 9.3 エッジケース

- [ ] 非常に小さいwait_time（0.01秒）
- [ ] 非常に大きいwait_time（60秒）
- [ ] リセット後は初回リクエスト扱い

### 9.4 システム時刻変更

- [ ] システム時刻を変更しても正常動作（CLOCK_MONOTONIC使用時）

## 10. パフォーマンス考慮

### 10.1 sleepの精度

Rubyの`sleep`は通常10ms程度の誤差がある。
待機時間が非常に短い場合（< 100ms）は注意が必要だが、通常は1秒以上なので問題なし。

### 10.2 オーバーヘッド

`Time.now`の呼び出しコストは無視できるレベル（マイクロ秒単位）。

## 11. 依存関係

なし（Ruby標準ライブラリのみ）

## 12. 実装の注意点

### 12.1 時刻の取得

```ruby
# 推奨: システム時刻変更の影響を受けない
Process.clock_gettime(Process::CLOCK_MONOTONIC)

# 非推奨: システム時刻変更の影響を受ける
Time.now
```

### 12.2 初期化時の@last_request_time

```ruby
# NG: 初期化時に現在時刻を設定すると初回も待機してしまう
@last_request_time = Time.now

# OK: 初回は待機しない
@last_request_time = nil
```

### 12.3 待機完了後の時刻更新

```ruby
def wait
  # ... 待機処理 ...
  
  # 重要: 待機後に現在時刻を記録
  @last_request_time = current_time
end
```

## 13. 統合例

### 13.1 Fetcherとの統合

```ruby
class Fetcher
  def initialize(base_url, rate_limiter)
    @base_url = base_url
    @rate_limiter = rate_limiter
  end
  
  def fetch(path)
    @rate_limiter.wait  # リクエスト前に待機
    
    url = "#{@base_url}#{path}"
    response = Faraday.get(url)
    
    response.body
  end
end
```

### 13.2 メインループでの使用

```ruby
site_config = config_loader.site('site_a')
rate_limiter = RateLimiter.new(
  site_config.actual_wait_time,
  enabled: !site_config.localhost?
)

urls.each_with_index do |url, index|
  logger.info("進捗: #{index + 1}/#{urls.size}")
  
  remaining = rate_limiter.remaining_wait_time
  logger.debug("待機: #{remaining.round(2)}秒") if remaining > 0
  
  rate_limiter.wait
  
  content = fetcher.fetch(url)
  storage.save(url, content)
end
```

## 14. 今後の拡張可能性

- スレッドセーフ対応（並行処理時）
- バーストリクエスト対応（短時間に複数可、その後待機）
- 指数バックオフ（エラー時の待機時間増加）
- リクエスト統計（平均間隔、合計待機時間）

## 15. 次のステップ

RateLimiterの仕様が確定したら、次は **Fetcher** に進みます。
