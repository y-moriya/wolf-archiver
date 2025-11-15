# RSpec設定ファイル
# frozen_string_literal: true

require 'pathname'
require 'webmock/rspec'
require_relative '../lib/wolf_archiver'

# テスト用のヘルパー
RSpec.configure do |config|
  # テストの実行順序をランダム化（デフォルト）
  config.order = :random

  # 警告を有効化
  config.warnings = true

  # 共有コンテキストとヘルパー
  config.shared_context_metadata_behavior = :apply_to_host_groups

  # フィルタリング
  config.filter_run_when_matching :focus

  # テストの実行例
  config.example_status_persistence_file_path = 'spec/examples.txt'

  # WebMock設定
  config.before(:each) do
    WebMock.disable_net_connect!(allow_localhost: true)
  end

  # カバレッジ（必要に応じて）
  # config.profile_examples = 10
end

