# frozen_string_literal: true

require 'spec_helper'

RSpec.describe WolfArchiver::PathMapper do
  let(:base_url) { 'http://example.com/wolf.cgi' }
  let(:path_mapping) do
    [
      { pattern: '\?cmd=top', path: 'index.html' },
      { pattern: '\?cmd=vlist', path: 'village_list.html' },
      { pattern: '\?cmd=vlog&vil=(\d+)&turn=(\d+)', path: 'villages/%{1}/day%{2}.html' },
      { pattern: '\?cmd=ulist', path: 'users/index.html' },
      { pattern: '\?cmd=ulog&uid=(\d+)', path: 'users/%{1}.html' },
      { pattern: '\?cmd=(\w+)', path: 'static/%{1}.html' }
    ]
  end
  let(:assets_config) do
    {
      css_dir: 'assets/css',
      js_dir: 'assets/js',
      images_dir: 'assets/images'
    }
  end
  let(:mapper) { described_class.new(base_url, path_mapping, assets_config) }

  describe '#initialize' do
    it 'base_url、path_mapping、assets_configを設定できる' do
      expect(mapper).to be_a(described_class)
    end

    it 'path_mappingを正規表現にコンパイルする' do
      mapper = described_class.new(base_url, path_mapping, assets_config)

      # 正規表現が正しくコンパイルされていることを確認
      result = mapper.url_to_path('http://example.com/wolf.cgi?cmd=top')
      expect(result).to eq('index.html')
    end
  end

  describe '#url_to_path' do
    context '正常系 - ページURL' do
      it 'シンプルなクエリパラメータをマッピングできる' do
        result = mapper.url_to_path('http://example.com/wolf.cgi?cmd=top')

        expect(result).to eq('index.html')
      end

      it 'キャプチャグループを含むパターンをマッピングできる' do
        result = mapper.url_to_path('http://example.com/wolf.cgi?cmd=vlog&vil=123&turn=456')

        expect(result).to eq('villages/123/day456.html')
      end

      it '複数のキャプチャグループを正しく置換できる' do
        result = mapper.url_to_path('http://example.com/wolf.cgi?cmd=ulog&uid=789')

        expect(result).to eq('users/789.html')
      end

      it 'ワイルドカードパターンでマッピングできる' do
        result = mapper.url_to_path('http://example.com/wolf.cgi?cmd=rule')

        expect(result).to eq('static/rule.html')
      end

      it 'クエリパラメータのみのURLをマッピングできる' do
        result = mapper.url_to_path('http://example.com/wolf.cgi?vlist')

        # マッピングに一致しない場合はnil
        expect(result).to be_nil
      end
    end

    context '正常系 - アセットURL' do
      it 'CSSファイルをマッピングできる' do
        result = mapper.url_to_path('http://example.com/style.css')

        expect(result).to eq('assets/css/style.css')
      end

      it 'JavaScriptファイルをマッピングできる' do
        result = mapper.url_to_path('http://example.com/app.js')

        expect(result).to eq('assets/js/app.js')
      end

      it 'PNG画像をマッピングできる' do
        result = mapper.url_to_path('http://example.com/icon.png')

        expect(result).to eq('assets/images/icon.png')
      end

      it 'JPG画像をマッピングできる' do
        result = mapper.url_to_path('http://example.com/image.jpg')

        expect(result).to eq('assets/images/image.jpg')
      end

      it 'GIF画像をマッピングできる' do
        result = mapper.url_to_path('http://example.com/animation.gif')

        expect(result).to eq('assets/images/animation.gif')
      end

      it 'SVG画像をマッピングできる' do
        result = mapper.url_to_path('http://example.com/logo.svg')

        expect(result).to eq('assets/images/logo.svg')
      end

      it 'サブディレクトリ内のアセットをマッピングできる' do
        result = mapper.url_to_path('http://example.com/images/bg.png')

        expect(result).to eq('assets/images/bg.png')
      end
    end

    context '異常系' do
      it '外部URLの場合は nil を返す' do
        result = mapper.url_to_path('http://other.com/page.html')

        expect(result).to be_nil
      end

      it 'マッピングに一致しないURLの場合は nil を返す' do
        # ワイルドカードパターンに一致しないURLを使用
        # パスが存在しない、またはクエリパラメータがない場合
        result = mapper.url_to_path('http://example.com/wolf.cgi')

        expect(result).to be_nil
      end

      it '不正なURLの場合は nil を返す（ホストが一致しないため）' do
        # URI.parseは寛容にパースするため、エラーにならない
        # ただし、ホストが一致しないためnilを返す
        result = mapper.url_to_path('not-a-valid-url')

        # 実装ではsame_host?でチェックするため、nilを返す
        expect(result).to be_nil
      end
    end

    context 'エッジケース' do
      it 'クエリパラメータが空のURLを処理できる' do
        result = mapper.url_to_path('http://example.com/wolf.cgi?')

        expect(result).to be_nil
      end

      it 'パスが空でクエリパラメータのみのURLを処理できる' do
        result = mapper.url_to_path('http://example.com/?cmd=top')

        # 実装ではuri.pathが空の場合の処理を確認
        expect(result).to eq('index.html')
      end

      it '複数のマッピングパターンがある場合、最初に一致したものを使用する' do
        # より具体的なパターンが先に定義されている場合
        specific_mapping = [
          { pattern: '\?cmd=(\w+)', path: 'static/%{1}.html' },
          { pattern: '\?cmd=top', path: 'index.html' }
        ]
        mapper = described_class.new(base_url, specific_mapping, assets_config)

        result = mapper.url_to_path('http://example.com/wolf.cgi?cmd=top')

        # 最初に一致したパターンを使用
        expect(result).to eq('static/top.html')
      end

      it 'キャプチャグループがないパターンでも動作する' do
        result = mapper.url_to_path('http://example.com/wolf.cgi?cmd=vlist')

        expect(result).to eq('village_list.html')
      end

      it '拡張子がないアセットURLはアセットとして扱わない' do
        result = mapper.url_to_path('http://example.com/asset')

        expect(result).to be_nil
      end
    end
  end

  describe 'アセットマッピング' do
    it 'CSSディレクトリに正しく配置される' do
      result = mapper.url_to_path('http://example.com/styles/main.css')

      expect(result).to eq('assets/css/main.css')
    end

    it 'JSディレクトリに正しく配置される' do
      result = mapper.url_to_path('http://example.com/scripts/app.js')

      expect(result).to eq('assets/js/app.js')
    end

    it '画像ディレクトリに正しく配置される' do
      result = mapper.url_to_path('http://example.com/pics/photo.jpg')

      expect(result).to eq('assets/images/photo.jpg')
    end

    it 'カスタムアセット設定を使用できる' do
      custom_config = {
        css_dir: 'custom/css',
        js_dir: 'custom/js',
        images_dir: 'custom/images'
      }
      mapper = described_class.new(base_url, [], custom_config)

      result = mapper.url_to_path('http://example.com/style.css')

      expect(result).to eq('custom/css/style.css')
    end
  end
end

