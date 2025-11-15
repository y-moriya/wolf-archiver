# frozen_string_literal: true

require 'spec_helper'

RSpec.describe WolfArchiver::Parser do
  let(:base_url) { 'http://example.com' }
  let(:parser) { described_class.new(base_url) }

  describe '#initialize' do
    it 'base_urlを設定できる' do
      expect(parser).to be_a(described_class)
    end
  end

  describe '#parse' do
    context '正常系' do
      it '基本的なHTMLのパースができる' do
        html = '<html><body><p>Test</p></body></html>'
        result = parser.parse(html, 'http://example.com/page.html')

        expect(result).to be_a(WolfArchiver::ParseResult)
        expect(result.document).to be_a(Nokogiri::HTML::Document)
        expect(result.links).to be_an(Array)
        expect(result.assets).to be_an(Array)
        expect(result.inline_assets).to be_an(Array)
      end

      it '相対URLを絶対URLに変換できる' do
        html = '<a href="page.html">Link</a>'
        result = parser.parse(html, 'http://example.com/index.html')

        expect(result.links.length).to eq(1)
        expect(result.links.first.url).to eq('http://example.com/page.html')
      end

      it '<a>タグのリンクを抽出できる' do
        html = '<a href="page1.html">Page 1</a><a href="page2.html">Page 2</a>'
        result = parser.parse(html, 'http://example.com/index.html')

        expect(result.links.length).to eq(2)
        expect(result.links.map(&:url)).to contain_exactly(
          'http://example.com/page1.html',
          'http://example.com/page2.html'
        )
        expect(result.links.first.text).to eq('Page 1')
      end

      it '<link rel="stylesheet">のCSSを抽出できる' do
        html = '<link rel="stylesheet" href="style.css">'
        result = parser.parse(html, 'http://example.com/index.html')

        expect(result.assets.length).to eq(1)
        expect(result.assets.first.type).to eq(:css)
        expect(result.assets.first.url).to eq('http://example.com/style.css')
      end

      it '<script src>のJavaScriptを抽出できる' do
        html = '<script src="app.js"></script>'
        result = parser.parse(html, 'http://example.com/index.html')

        expect(result.assets.length).to eq(1)
        expect(result.assets.first.type).to eq(:js)
        expect(result.assets.first.url).to eq('http://example.com/app.js')
      end

      it '<img src>の画像を抽出できる' do
        html = '<img src="image.png" alt="Test">'
        result = parser.parse(html, 'http://example.com/index.html')

        expect(result.assets.length).to eq(1)
        expect(result.assets.first.type).to eq(:image)
        expect(result.assets.first.url).to eq('http://example.com/image.png')
      end

      it 'インラインCSSからURLを抽出できる' do
        html = '<style>body { background: url("bg.png"); }</style>'
        result = parser.parse(html, 'http://example.com/index.html')

        expect(result.inline_assets.length).to eq(1)
        expect(result.inline_assets.first.type).to eq(:inline_css)
        expect(result.inline_assets.first.urls).to include('http://example.com/bg.png')
      end

      it '<base>タグを処理できる' do
        html = '<base href="http://other.com/"><a href="page.html">Link</a>'
        result = parser.parse(html, 'http://example.com/index.html')

        expect(result.links.length).to eq(1)
        expect(result.links.first.url).to eq('http://other.com/page.html')
      end

      it 'プロトコル相対URL（//example.com）を処理できる' do
        html = '<a href="//other.com/page.html">Link</a>'
        result = parser.parse(html, 'http://example.com/index.html')

        expect(result.links.length).to eq(1)
        expect(result.links.first.url).to eq('http://other.com/page.html')
      end

      it 'フラグメント（#anchor）を除去する' do
        html = '<a href="page.html#section1">Link</a>'
        result = parser.parse(html, 'http://example.com/index.html')

        expect(result.links.length).to eq(1)
        expect(result.links.first.url).to eq('http://example.com/page.html')
      end

      it 'all_urlsですべてのURLを取得できる' do
        html = '<a href="page.html">Link</a><img src="img.png"><link rel="stylesheet" href="style.css">'
        result = parser.parse(html, 'http://example.com/index.html')

        urls = result.all_urls
        expect(urls).to include('http://example.com/page.html')
        expect(urls).to include('http://example.com/img.png')
        expect(urls).to include('http://example.com/style.css')
      end
    end

    context '異常系・スキップ' do
      it 'アンカーリンク（#）をスキップする' do
        html = '<a href="#section">Anchor</a>'
        result = parser.parse(html, 'http://example.com/index.html')

        expect(result.links).to be_empty
      end

      it 'JavaScriptスキームをスキップする' do
        html = '<a href="javascript:void(0)">JS Link</a>'
        result = parser.parse(html, 'http://example.com/index.html')

        expect(result.links).to be_empty
      end

      it 'mailtoスキームをスキップする' do
        html = '<a href="mailto:test@example.com">Email</a>'
        result = parser.parse(html, 'http://example.com/index.html')

        expect(result.links).to be_empty
      end

      it 'Data URIをスキップする' do
        html = '<img src="data:image/png;base64,iVBORw0KGgo=">'
        result = parser.parse(html, 'http://example.com/index.html')

        expect(result.assets).to be_empty
      end

      it '空のHTMLを処理できる' do
        html = ''
        result = parser.parse(html, 'http://example.com/index.html')

        expect(result.links).to be_empty
        expect(result.assets).to be_empty
      end

      it '不正なURLをスキップする' do
        # Addressable::URIは寛容にパースするため、完全に無効なURLを使用
        # 実際には空文字列や特殊文字のみのURLをスキップすることを確認
        html = '<a href="">Empty</a><a href="   ">Whitespace</a>'
        result = parser.parse(html, 'http://example.com/index.html')

        expect(result.links).to be_empty
      end
    end

    context 'エッジケース' do
      it 'クエリパラメータ付きURLを処理できる' do
        html = '<a href="page.html?id=123">Link</a>'
        result = parser.parse(html, 'http://example.com/index.html')

        expect(result.links.first.url).to eq('http://example.com/page.html?id=123')
      end

      it '相対パス（../）を解決できる' do
        html = '<a href="../parent.html">Parent</a>'
        result = parser.parse(html, 'http://example.com/dir/page.html')

        expect(result.links.first.url).to eq('http://example.com/parent.html')
      end

      it '絶対URLはそのまま使用する' do
        html = '<a href="http://other.com/page.html">External</a>'
        result = parser.parse(html, 'http://example.com/index.html')

        expect(result.links.first.url).to eq('http://other.com/page.html')
      end

      it '壊れたHTMLでもパースできる' do
        html = '<html><body><p>Test</body>'
        result = parser.parse(html, 'http://example.com/index.html')

        expect(result).to be_a(WolfArchiver::ParseResult)
      end
    end
  end
end

RSpec.describe WolfArchiver::Link do
  let(:base_domain) { 'example.com' }
  let(:element) { Nokogiri::HTML('<a href="test.html">Test</a>').at_css('a') }

  describe '#internal?' do
    it '同一ドメインの場合は true を返す' do
      link = described_class.new(
        url: 'http://example.com/page.html',
        element: element,
        attribute: 'href'
      )

      expect(link.internal?(base_domain)).to be true
    end

    it 'サブドメインの場合は true を返す' do
      link = described_class.new(
        url: 'http://sub.example.com/page.html',
        element: element,
        attribute: 'href'
      )

      expect(link.internal?(base_domain)).to be true
    end

    it '異なるドメインの場合は false を返す' do
      link = described_class.new(
        url: 'http://other.com/page.html',
        element: element,
        attribute: 'href'
      )

      expect(link.internal?(base_domain)).to be false
    end
  end

  describe '#external?' do
    it 'internal?の逆を返す' do
      link = described_class.new(
        url: 'http://other.com/page.html',
        element: element,
        attribute: 'href'
      )

      expect(link.external?(base_domain)).to be true
      expect(link.external?(base_domain)).to eq(!link.internal?(base_domain))
    end
  end

  describe '#anchor?' do
    it '#で始まるURLの場合は true を返す' do
      link = described_class.new(
        url: '#section',
        element: element,
        attribute: 'href'
      )

      expect(link.anchor?).to be true
    end

    it '通常のURLの場合は false を返す' do
      link = described_class.new(
        url: 'http://example.com/page.html',
        element: element,
        attribute: 'href'
      )

      expect(link.anchor?).to be false
    end
  end
end

RSpec.describe WolfArchiver::Asset do
  let(:element) { Nokogiri::HTML('<link rel="stylesheet" href="style.css">').at_css('link') }

  describe '#extension' do
    it 'CSSアセットの場合は .css を返す' do
      asset = described_class.new(
        url: 'http://example.com/style.css',
        type: :css,
        element: element,
        attribute: 'href'
      )

      expect(asset.extension).to eq('.css')
    end

    it 'JavaScriptアセットの場合は .js を返す' do
      element = Nokogiri::HTML('<script src="app.js"></script>').at_css('script')
      asset = described_class.new(
        url: 'http://example.com/app.js',
        type: :js,
        element: element,
        attribute: 'src'
      )

      expect(asset.extension).to eq('.js')
    end

    it '画像アセットの場合は拡張子を返す' do
      element = Nokogiri::HTML('<img src="image.png">').at_css('img')
      asset = described_class.new(
        url: 'http://example.com/image.png',
        type: :image,
        element: element,
        attribute: 'src'
      )

      expect(asset.extension).to eq('.png')
    end

    it '拡張子がない画像の場合は .png を返す' do
      element = Nokogiri::HTML('<img src="image">').at_css('img')
      asset = described_class.new(
        url: 'http://example.com/image',
        type: :image,
        element: element,
        attribute: 'src'
      )

      expect(asset.extension).to eq('.png')
    end
  end
end

RSpec.describe WolfArchiver::ParseResult do
  let(:document) { Nokogiri::HTML('<html></html>') }
  let(:links) { [] }
  let(:assets) { [] }
  let(:inline_assets) { [] }

  describe '#all_urls' do
    it 'リンク、アセット、インラインアセットのURLを統合する' do
      link_element = Nokogiri::HTML('<a href="page.html">Link</a>').at_css('a')
      link = WolfArchiver::Link.new(
        url: 'http://example.com/page.html',
        element: link_element,
        attribute: 'href'
      )

      asset_element = Nokogiri::HTML('<img src="img.png">').at_css('img')
      asset = WolfArchiver::Asset.new(
        url: 'http://example.com/img.png',
        type: :image,
        element: asset_element,
        attribute: 'src'
      )

      inline_element = Nokogiri::HTML('<style>body { background: url("bg.png"); }</style>').at_css('style')
      inline = WolfArchiver::InlineAsset.new(
        urls: ['http://example.com/bg.png'],
        type: :inline_css,
        element: inline_element,
        content: 'body { background: url("bg.png"); }'
      )

      result = described_class.new(
        document: document,
        links: [link],
        assets: [asset],
        inline_assets: [inline]
      )

      urls = result.all_urls
      expect(urls).to include('http://example.com/page.html')
      expect(urls).to include('http://example.com/img.png')
      expect(urls).to include('http://example.com/bg.png')
    end

    it '重複URLを除去する' do
      link_element = Nokogiri::HTML('<a href="page.html">Link</a>').at_css('a')
      link = WolfArchiver::Link.new(
        url: 'http://example.com/page.html',
        element: link_element,
        attribute: 'href'
      )

      asset_element = Nokogiri::HTML('<img src="page.html">').at_css('img')
      asset = WolfArchiver::Asset.new(
        url: 'http://example.com/page.html',
        type: :image,
        element: asset_element,
        attribute: 'src'
      )

      result = described_class.new(
        document: document,
        links: [link],
        assets: [asset],
        inline_assets: []
      )

      expect(result.all_urls.length).to eq(1)
      expect(result.all_urls).to eq(['http://example.com/page.html'])
    end
  end
end

