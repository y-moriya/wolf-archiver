source 'https://rubygems.org'

ruby '3.2.0'

# Core dependencies
gem 'nokogiri'        # HTML解析
gem 'faraday'         # HTTP通信
gem 'addressable'     # URL処理
gem 'mime-types'      # MIME type検出

# CLI
gem 'thor'            # CLIフレームワーク
gem 'tty-progressbar' # プログレス表示

# Development/Testing
group :development, :test do
  gem 'rspec'         # テストフレームワーク
  gem 'webmock'       # HTTP mocking
  gem 'vcr'           # HTTPレコーディング
  gem 'pry'           # REPL
  gem 'pry-byebug'    # デバッガ
end

group :development do
  gem 'rubocop'       # Linter
  gem 'yard'          # ドキュメント生成
end
