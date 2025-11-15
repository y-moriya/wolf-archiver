# frozen_string_literal: true

require 'spec_helper'
require 'wolf_archiver/asset_downloader'
require 'wolf_archiver/fetcher'
require 'wolf_archiver/storage'
require 'wolf_archiver/path_mapper'
require 'wolf_archiver/parser'
require 'set'
require 'tempfile'

RSpec.describe WolfArchiver::AssetDownloader do
  let(:base_url) { 'http://example.com/wolf.cgi' }
  let(:rate_limiter) { WolfArchiver::RateLimiter.new(0.1) }
  let(:fetcher) { WolfArchiver::Fetcher.new(base_url, rate_limiter) }
  let(:temp_dir) { Dir.mktmpdir }
  let(:storage) { WolfArchiver::Storage.new(temp_dir) }
  let(:path_mapping) do
    [
      { pattern: '\?cmd=top', path: 'index.html' }
    ]
  end
  let(:assets_config) do
    {
      css_dir: 'assets/css',
      js_dir: 'assets/js',
      images_dir: 'assets/images'
    }
  end
  let(:path_mapper) { WolfArchiver::PathMapper.new(base_url, path_mapping, assets_config) }
  let(:downloader) { described_class.new(fetcher, storage, path_mapper) }
  let(:parser) { WolfArchiver::Parser.new(base_url) }

  after do
    FileUtils.rm_rf(temp_dir) if Dir.exist?(temp_dir)
  end

  describe '#download' do
    context '正常系' do
      it '単一のCSSファイルをダウンロードできる' do
        html = '<html><head><link rel="stylesheet" href="http://example.com/style.css"></head></html>'
        parse_result = parser.parse(html, base_url)
        assets = parse_result.assets

        stub_request(:get, 'http://example.com/style.css')
          .to_return(status: 200, body: 'body { color: red; }', headers: { 'Content-Type' => 'text/css' })

        result = downloader.download(assets)

        expect(result.succeeded.size).to eq(1)
        expect(result.succeeded.first).to eq('assets/css/style.css')
        expect(result.failed.size).to eq(0)
        expect(result.skipped.size).to eq(0)
        expect(storage.exist?('assets/css/style.css')).to be true
        expect(storage.read('assets/css/style.css')).to eq('body { color: red; }')
      end

      it '複数のアセットをダウンロードできる' do
        html = <<~HTML
          <html>
            <head>
              <link rel="stylesheet" href="http://example.com/style.css">
              <script src="http://example.com/script.js"></script>
            </head>
            <body>
              <img src="http://example.com/icon.png">
            </body>
          </html>
        HTML
        parse_result = parser.parse(html, base_url)
        assets = parse_result.assets

        stub_request(:get, 'http://example.com/style.css')
          .to_return(status: 200, body: 'body { color: red; }', headers: { 'Content-Type' => 'text/css' })
        stub_request(:get, 'http://example.com/script.js')
          .to_return(status: 200, body: 'console.log("test");', headers: { 'Content-Type' => 'application/javascript' })
        stub_request(:get, 'http://example.com/icon.png')
          .to_return(status: 200, body: "\x89PNG\r\n\x1a\n".dup.force_encoding('BINARY'), headers: { 'Content-Type' => 'image/png' })

        result = downloader.download(assets)

        expect(result.succeeded.size).to eq(3)
        expect(result.failed.size).to eq(0)
        expect(result.skipped.size).to eq(0)
        expect(storage.exist?('assets/css/style.css')).to be true
        expect(storage.exist?('assets/js/script.js')).to be true
        expect(storage.exist?('assets/images/icon.png')).to be true
      end

      it '重複URLを除去してダウンロードする' do
        html = <<~HTML
          <html>
            <head>
              <link rel="stylesheet" href="http://example.com/style.css">
              <link rel="stylesheet" href="http://example.com/style.css">
            </head>
          </html>
        HTML
        parse_result = parser.parse(html, base_url)
        assets = parse_result.assets

        stub_request(:get, 'http://example.com/style.css')
          .to_return(status: 200, body: 'body { color: red; }', headers: { 'Content-Type' => 'text/css' })

        result = downloader.download(assets)

        expect(result.succeeded.size).to eq(1)
        expect(result.total).to eq(1)
      end

      it '既存ファイルをスキップする' do
        html = '<html><head><link rel="stylesheet" href="http://example.com/style.css"></head></html>'
        parse_result = parser.parse(html, base_url)
        assets = parse_result.assets

        # 事前にファイルを作成
        storage.save_binary('assets/css/style.css', 'existing content')

        result = downloader.download(assets)

        expect(result.succeeded.size).to eq(0)
        expect(result.skipped.size).to eq(1)
        expect(result.skipped.first).to eq('http://example.com/style.css')
      end
    end

    context '異常系' do
      it '404エラーのアセットをfailedに追加して継続する' do
        html = '<html><head><link rel="stylesheet" href="http://example.com/missing.css"></head></html>'
        parse_result = parser.parse(html, base_url)
        assets = parse_result.assets

        stub_request(:get, 'http://example.com/missing.css')
          .to_return(status: 404, body: 'Not Found')

        result = downloader.download(assets)

        expect(result.succeeded.size).to eq(0)
        expect(result.failed.size).to eq(1)
        expect(result.failed.first[:url]).to eq('http://example.com/missing.css')
      end

      it 'タイムアウトエラーのアセットをfailedに追加して継続する' do
        html = '<html><head><script src="http://example.com/slow.js"></script></head></html>'
        parse_result = parser.parse(html, base_url)
        assets = parse_result.assets

        stub_request(:get, 'http://example.com/slow.js')
          .to_raise(Faraday::TimeoutError.new('timeout'))

        result = downloader.download(assets)

        expect(result.succeeded.size).to eq(0)
        expect(result.failed.size).to eq(1)
        expect(result.failed.first[:url]).to eq('http://example.com/slow.js')
      end

      it 'マッピング不可のアセットをfailedに追加して継続する' do
        html = '<html><head><link rel="stylesheet" href="http://other.com/external.css"></head></html>'
        parse_result = parser.parse(html, base_url)
        assets = parse_result.assets

        result = downloader.download(assets)

        expect(result.succeeded.size).to eq(0)
        expect(result.failed.size).to eq(1)
        expect(result.failed.first[:url]).to eq('http://other.com/external.css')
        expect(result.failed.first[:error]).to eq('Unknown error')
      end

      it '部分的に失敗しても成功したアセットは保存される' do
        html = <<~HTML
          <html>
            <head>
              <link rel="stylesheet" href="http://example.com/style.css">
              <script src="http://example.com/missing.js"></script>
            </head>
          </html>
        HTML
        parse_result = parser.parse(html, base_url)
        assets = parse_result.assets

        stub_request(:get, 'http://example.com/style.css')
          .to_return(status: 200, body: 'body { color: red; }', headers: { 'Content-Type' => 'text/css' })
        stub_request(:get, 'http://example.com/missing.js')
          .to_return(status: 404, body: 'Not Found')

        result = downloader.download(assets)

        expect(result.succeeded.size).to eq(1)
        expect(result.failed.size).to eq(1)
        expect(storage.exist?('assets/css/style.css')).to be true
      end
    end

    context 'エッジケース' do
      it '0件のアセットでも動作する' do
        assets = []

        result = downloader.download(assets)

        expect(result.succeeded.size).to eq(0)
        expect(result.failed.size).to eq(0)
        expect(result.skipped.size).to eq(0)
        expect(result.total).to eq(0)
      end

      it 'すべてスキップ（既存）でも動作する' do
        html = '<html><head><link rel="stylesheet" href="http://example.com/style.css"></head></html>'
        parse_result = parser.parse(html, base_url)
        assets = parse_result.assets

        # 事前にファイルを作成
        storage.save_binary('assets/css/style.css', 'existing content')

        result = downloader.download(assets)

        expect(result.succeeded.size).to eq(0)
        expect(result.failed.size).to eq(0)
        expect(result.skipped.size).to eq(1)
        expect(result.total).to eq(1)
      end

      it 'バイナリデータを正しく保存できる' do
        html = '<html><body><img src="http://example.com/image.png"></body></html>'
        parse_result = parser.parse(html, base_url)
        assets = parse_result.assets

        # シンプルなバイナリデータ（改行文字を含まない）
        binary_data = "\x89PNG\x1a\x00\x00\x00\x0dIHDR".dup.force_encoding('BINARY')
        stub_request(:get, 'http://example.com/image.png')
          .to_return(status: 200, body: binary_data, headers: { 'Content-Type' => 'image/png' })

        result = downloader.download(assets)

        expect(result.succeeded.size).to eq(1)
        saved_data = storage.read('assets/images/image.png', encoding: 'BINARY')
        expect(saved_data.encoding).to eq(Encoding::BINARY)
        # バイナリデータが正しく保存されていることを確認
        expect(saved_data).to eq(binary_data)
        expect(saved_data.bytesize).to eq(binary_data.bytesize)
      end
    end
  end

  describe '#download_single' do
    context '正常系' do
      it 'アセットをダウンロードして保存できる' do
        html = '<html><head><link rel="stylesheet" href="http://example.com/style.css"></head></html>'
        parse_result = parser.parse(html, base_url)
        asset = parse_result.assets.first

        stub_request(:get, 'http://example.com/style.css')
          .to_return(status: 200, body: 'body { color: red; }', headers: { 'Content-Type' => 'text/css' })

        result = downloader.download_single(asset)

        expect(result).to eq('assets/css/style.css')
        expect(storage.exist?('assets/css/style.css')).to be true
        expect(storage.read('assets/css/style.css')).to eq('body { color: red; }')
      end

      it '既存ファイルの場合は:skippedを返す' do
        html = '<html><head><link rel="stylesheet" href="http://example.com/style.css"></head></html>'
        parse_result = parser.parse(html, base_url)
        asset = parse_result.assets.first

        # 事前にファイルを作成
        storage.save_binary('assets/css/style.css', 'existing content')

        result = downloader.download_single(asset)

        expect(result).to eq(:skipped)
      end

      it 'マッピング不可の場合はnilを返す' do
        html = '<html><head><link rel="stylesheet" href="http://other.com/external.css"></head></html>'
        parse_result = parser.parse(html, base_url)
        asset = parse_result.assets.first

        result = downloader.download_single(asset)

        expect(result).to be_nil
      end
    end

    context '異常系' do
      it '404エラーの場合はnilを返す' do
        html = '<html><head><link rel="stylesheet" href="http://example.com/missing.css"></head></html>'
        parse_result = parser.parse(html, base_url)
        asset = parse_result.assets.first

        stub_request(:get, 'http://example.com/missing.css')
          .to_return(status: 404, body: 'Not Found')

        result = downloader.download_single(asset)

        expect(result).to be_nil
      end

      it 'FetchErrorをキャッチしてnilを返す（404などのHTTPエラー）' do
        html = '<html><head><script src="http://example.com/script.js"></script></head></html>'
        parse_result = parser.parse(html, base_url)
        asset = parse_result.assets.first

        stub_request(:get, 'http://example.com/script.js')
          .to_return(status: 500, body: 'Internal Server Error')

        result = downloader.download_single(asset)

        expect(result).to be_nil
      end

      it 'StorageErrorをキャッチしてAssetDownloaderErrorを発生させる' do
        html = '<html><head><link rel="stylesheet" href="http://example.com/style.css"></head></html>'
        parse_result = parser.parse(html, base_url)
        asset = parse_result.assets.first

        stub_request(:get, 'http://example.com/style.css')
          .to_return(status: 200, body: 'body { color: red; }', headers: { 'Content-Type' => 'text/css' })

        # Storageをモックしてエラーを発生させる
        allow(storage).to receive(:save_binary).and_raise(WolfArchiver::StorageError.new('Permission denied'))

        expect {
          downloader.download_single(asset)
        }.to raise_error(WolfArchiver::AssetDownloaderError, /アセット保存失敗/)
      end
    end
  end

  describe 'DownloadResult' do
    let(:result) do
      WolfArchiver::DownloadResult.new(
        succeeded: ['assets/css/style.css', 'assets/js/script.js'],
        failed: [{ url: 'http://example.com/missing.png', error: '404 Not Found' }],
        skipped: ['http://example.com/existing.png']
      )
    end

    describe '#initialize' do
      it 'succeeded、failed、skipped、totalを設定できる' do
        expect(result.succeeded.size).to eq(2)
        expect(result.failed.size).to eq(1)
        expect(result.skipped.size).to eq(1)
        expect(result.total).to eq(4)
      end
    end

    describe '#success_rate' do
      it '成功率を正しく計算できる' do
        rate = result.success_rate
        expect(rate).to be_within(0.01).of(2.0 / 3.0) # 2成功 / (2成功 + 1失敗)
      end

      it '0件の場合は1.0を返す' do
        empty_result = WolfArchiver::DownloadResult.new(
          succeeded: [],
          failed: [],
          skipped: []
        )
        expect(empty_result.success_rate).to eq(1.0)
      end

      it 'すべて失敗の場合は0.0を返す' do
        all_failed = WolfArchiver::DownloadResult.new(
          succeeded: [],
          failed: [{ url: 'http://example.com/missing.png', error: '404' }],
          skipped: []
        )
        expect(all_failed.success_rate).to eq(0.0)
      end
    end

    describe '#summary' do
      it 'サマリーを正しく出力できる' do
        summary = result.summary
        expect(summary).to include('アセットダウンロード結果')
        expect(summary).to include('成功: 2件')
        expect(summary).to include('失敗: 1件')
        expect(summary).to include('スキップ: 1件')
        expect(summary).to include('合計: 4件')
        expect(summary).to include('成功率')
      end
    end
  end

  describe '#initialize' do
    it 'fetcher、storage、path_mapperを設定できる' do
      downloader = described_class.new(fetcher, storage, path_mapper)

      expect(downloader).to be_a(described_class)
    end
  end
end

