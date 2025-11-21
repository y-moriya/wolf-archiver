# frozen_string_literal: true

require 'spec_helper'
require 'wolf_archiver/link_rewriter'
require 'wolf_archiver/path_mapper'
require 'wolf_archiver/parser'

RSpec.describe WolfArchiver::LinkRewriter do
  let(:base_domain) { 'example.com' }
  let(:base_url) { 'http://example.com/wolf.cgi' }
  let(:path_mapping) do
    [
      { pattern: '\?cmd=top', path: 'index.html' },
      { pattern: '\?cmd=vlog&vil=(\d+)&turn=(\d+)', path: 'villages/%{1}/day%{2}.html' }
    ]
  end

  let(:path_mapper) { WolfArchiver::PathMapper.new(base_url, path_mapping) }
  let(:downloaded_paths) { Set.new(['index.html', 'villages/1/day1.html', 'villages/1/day2.html']) }
  let(:rewriter) { described_class.new(base_domain, path_mapper, downloaded_paths) }
  let(:parser) { WolfArchiver::Parser.new(base_url) }

  describe '#calculate_relative_path' do
    context '正常系' do
      it '同じディレクトリのファイルを正しく計算できる' do
        result = rewriter.calculate_relative_path('index.html', 'about.html')

        expect(result).to eq('about.html')
      end

      it '下の階層へのパスを正しく計算できる' do
        result = rewriter.calculate_relative_path('index.html', 'style.css')

        expect(result).to eq('style.css')
      end

      it '上の階層へのパスを正しく計算できる' do
        result = rewriter.calculate_relative_path('villages/1/day1.html', 'index.html')

        expect(result).to eq('../../index.html')
      end

      it '異なる階層間のパスを正しく計算できる' do
        result = rewriter.calculate_relative_path('villages/1/day1.html', 'style.css')

        expect(result).to eq('../../style.css')
      end

      it '深い階層のパスを正しく計算できる' do
        result = rewriter.calculate_relative_path('villages/1/day1.html', 'villages/2/day3.html')

        expect(result).to eq('../2/day3.html')
      end

      it 'ルートからのパスを正しく計算できる' do
        result = rewriter.calculate_relative_path('index.html', 'index.html')

        expect(result).to eq('.')
      end

      it '同じファイルへのパスは"."を返す' do
        result = rewriter.calculate_relative_path('villages/1/day1.html', 'villages/1/day1.html')

        expect(result).to eq('.')
      end
    end

    context 'エッジケース' do
      it '非常に深い階層でも正しく計算できる' do
        from = 'a/b/c/d/e/f/g/h/i/j/file1.html'
        to = 'a/b/c/d/e/f/g/h/i/j/k/file2.html'

        result = rewriter.calculate_relative_path(from, to)

        expect(result).to eq('k/file2.html')
      end

      it '日本語を含むパスでも正しく計算できる' do
        from = '村/1/日1.html'
        to = '村/2/日2.html'

        result = rewriter.calculate_relative_path(from, to)

        expect(result).to eq('../2/日2.html')
      end

      it 'パスが正規化される' do
        from = 'villages/1/../2/day1.html'
        to = 'villages/2/day2.html'

        result = rewriter.calculate_relative_path(from, to)

        expect(result).to eq('day2.html')
      end

      it 'キャッシュが機能する' do
        from = 'index.html'
        to = 'about.html'

        result1 = rewriter.calculate_relative_path(from, to)
        result2 = rewriter.calculate_relative_path(from, to)

        expect(result1).to eq(result2)
        expect(result1).to eq('about.html')
      end
    end
  end

  describe '#rewrite' do
    context 'ページリンクの書き換え' do
      it '内部リンクを相対パスに書き換える' do
        html = '<html><body><a href="http://example.com/wolf.cgi?cmd=top">トップ</a></body></html>'
        parse_result = parser.parse(html, base_url)
        current_path = 'villages/1/day1.html'

        result = rewriter.rewrite(parse_result, current_path)

        doc = Nokogiri::HTML(result)
        link = doc.at_css('a[href]')
        expect(link['href']).to eq('../../index.html')
      end

      it '外部リンクをそのまま保持する' do
        html = '<html><body><a href="http://other.com/page.html">外部リンク</a></body></html>'
        parse_result = parser.parse(html, base_url)
        current_path = 'index.html'

        result = rewriter.rewrite(parse_result, current_path)

        doc = Nokogiri::HTML(result)
        link = doc.at_css('a[href]')
        expect(link['href']).to eq('http://other.com/page.html')
      end

      it 'マッピング不可のリンクを#に書き換える' do
        html = '<html><body><a href="http://example.com/wolf.cgi?cmd=unknown">不明なページ</a></body></html>'
        parse_result = parser.parse(html, base_url)
        current_path = 'index.html'

        result = rewriter.rewrite(parse_result, current_path)

        doc = Nokogiri::HTML(result)
        link = doc.at_css('a[href]')
        expect(link['href']).to eq('#')
      end

      it '未ダウンロードのリンクを#に書き換える' do
        html = '<html><body><a href="http://example.com/wolf.cgi?cmd=vlog&vil=999&turn=1">未ダウンロード</a></body></html>'
        parse_result = parser.parse(html, base_url)
        current_path = 'index.html'

        result = rewriter.rewrite(parse_result, current_path)

        doc = Nokogiri::HTML(result)
        link = doc.at_css('a[href]')
        expect(link['href']).to eq('#')
      end

      it 'アンカーリンクをそのまま保持する' do
        html = '<html><body><a href="#section1">セクション1</a></body></html>'
        parse_result = parser.parse(html, base_url)
        current_path = 'index.html'

        result = rewriter.rewrite(parse_result, current_path)

        doc = Nokogiri::HTML(result)
        link = doc.at_css('a[href]')
        expect(link['href']).to eq('#section1')
      end

      it '複数のリンクを正しく書き換える' do
        html = <<~HTML
          <html>
            <body>
              <a href="http://example.com/wolf.cgi?cmd=top">トップ</a>
              <a href="http://example.com/wolf.cgi?cmd=vlog&vil=1&turn=2">日2</a>
              <a href="http://other.com/page.html">外部</a>
            </body>
          </html>
        HTML
        parse_result = parser.parse(html, base_url)
        current_path = 'villages/1/day1.html'

        result = rewriter.rewrite(parse_result, current_path)

        doc = Nokogiri::HTML(result)
        links = doc.css('a[href]')
        expect(links[0]['href']).to eq('../../index.html')
        expect(links[1]['href']).to eq('day2.html')
        expect(links[2]['href']).to eq('http://other.com/page.html')
      end
    end

    context 'アセットの書き換え' do
      it 'CSSファイルを相対パスに書き換える' do
        html = '<html><head><link rel="stylesheet" href="http://example.com/style.css"></head></html>'
        parse_result = parser.parse(html, base_url)
        current_path = 'villages/1/day1.html'

        result = rewriter.rewrite(parse_result, current_path)

        doc = Nokogiri::HTML(result)
        link = doc.at_css('link[rel="stylesheet"]')
        expect(link['href']).to eq('../../style.css')
      end

      it 'JavaScriptファイルを相対パスに書き換える' do
        html = '<html><head><script src="http://example.com/script.js"></script></head></html>'
        parse_result = parser.parse(html, base_url)
        current_path = 'index.html'

        result = rewriter.rewrite(parse_result, current_path)

        doc = Nokogiri::HTML(result)
        script = doc.at_css('script[src]')
        expect(script['src']).to eq('script.js')
      end

      it '画像ファイルを相対パスに書き換える' do
        html = '<html><body><img src="http://example.com/icon.png"></body></html>'
        parse_result = parser.parse(html, base_url)
        current_path = 'index.html'

        result = rewriter.rewrite(parse_result, current_path)

        doc = Nokogiri::HTML(result)
        img = doc.at_css('img[src]')
        expect(img['src']).to eq('icon.png')
      end

      it 'マッピング不可のアセットを#に書き換える' do
        html = '<html><body><img src="http://example.com/unknown.xyz"></body></html>'
        parse_result = parser.parse(html, base_url)
        current_path = 'index.html'

        result = rewriter.rewrite(parse_result, current_path)

        doc = Nokogiri::HTML(result)
        img = doc.at_css('img[src]')
        expect(img['src']).to eq('#')
      end

      it '外部アセットをそのまま保持する' do
        html = '<html><body><img src="http://other.com/image.png"></body></html>'
        parse_result = parser.parse(html, base_url)
        current_path = 'index.html'

        result = rewriter.rewrite(parse_result, current_path)

        doc = Nokogiri::HTML(result)
        img = doc.at_css('img[src]')
        expect(img['src']).to eq('http://other.com/image.png')
      end

      it '複数のアセットを正しく書き換える' do
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
        current_path = 'villages/1/day1.html'

        result = rewriter.rewrite(parse_result, current_path)

        doc = Nokogiri::HTML(result)
        css = doc.at_css('link[rel="stylesheet"]')
        js = doc.at_css('script[src]')
        img = doc.at_css('img[src]')
        expect(css['href']).to eq('../../style.css')
        expect(js['src']).to eq('../../script.js')
        expect(img['src']).to eq('../../icon.png')
      end
    end

    context 'エラーハンドリング' do
      it 'HTML解析エラー時にLinkRewriterErrorを発生させる' do
        # 無効なParseResultを模擬
        parse_result = double('ParseResult')
        allow(parse_result).to receive(:document).and_raise(StandardError.new('Test error'))
        allow(parse_result).to receive(:links).and_return([])
        allow(parse_result).to receive(:assets).and_return([])

        expect do
          rewriter.rewrite(parse_result, 'index.html')
        end.to raise_error(WolfArchiver::LinkRewriterError, /リンク書き換えエラー/)
      end

      it '元のドキュメントが変更されない' do
        html = '<html><body><a href="http://example.com/wolf.cgi?cmd=top">トップ</a></body></html>'
        parse_result = parser.parse(html, base_url)
        original_href = parse_result.document.at_css('a[href]')['href']

        rewriter.rewrite(parse_result, 'index.html')

        # 元のドキュメントは変更されていない
        expect(parse_result.document.at_css('a[href]')['href']).to eq(original_href)
      end
    end

    context 'エッジケース' do
      it 'リンクがないHTMLでも動作する' do
        html = '<html><body><p>テキストのみ</p></body></html>'
        parse_result = parser.parse(html, base_url)

        expect do
          result = rewriter.rewrite(parse_result, 'index.html')
          expect(result).to be_a(String)
        end.not_to raise_error
      end

      it 'アセットがないHTMLでも動作する' do
        html = '<html><body><p>テキストのみ</p></body></html>'
        parse_result = parser.parse(html, base_url)

        expect do
          result = rewriter.rewrite(parse_result, 'index.html')
          expect(result).to be_a(String)
        end.not_to raise_error
      end

      it 'クエリパラメータを含むURLを正しく処理する' do
        html = '<html><body><a href="http://example.com/wolf.cgi?cmd=vlog&vil=1&turn=2">日2</a></body></html>'
        parse_result = parser.parse(html, base_url)
        current_path = 'villages/1/day1.html'

        result = rewriter.rewrite(parse_result, current_path)

        doc = Nokogiri::HTML(result)
        link = doc.at_css('a[href]')
        expect(link['href']).to eq('day2.html')
      end
    end
  end

  describe '#initialize' do
    it 'base_domain、path_mapper、downloaded_pathsを設定できる' do
      rewriter = described_class.new(base_domain, path_mapper, downloaded_paths)

      expect(rewriter).to be_a(described_class)
    end

    it '相対パスキャッシュを初期化する' do
      rewriter = described_class.new(base_domain, path_mapper, downloaded_paths)

      # キャッシュが機能することを確認
      result1 = rewriter.calculate_relative_path('index.html', 'about.html')
      result2 = rewriter.calculate_relative_path('index.html', 'about.html')

      expect(result1).to eq(result2)
    end
  end
end
