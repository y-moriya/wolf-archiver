# frozen_string_literal: true

require 'spec_helper'
require 'tempfile'
require 'fileutils'

RSpec.describe WolfArchiver::ConfigLoader do
  let(:temp_dir) { Dir.mktmpdir('wolf_archiver_test') }
  let(:config_path) { File.join(temp_dir, 'sites.yml') }

  after do
    FileUtils.rm_rf(temp_dir) if Dir.exist?(temp_dir)
  end

  def write_config(content)
    File.write(config_path, content)
  end

  describe '#initialize' do
    context '正常系' do
      it '最小限の設定で読み込める' do
        write_config(<<~YAML)
          sites:
            test_site:
              name: "テストサイト"
              base_url: "http://example.com/wolf.cgi"
              encoding: "UTF-8"
              wait_time: 1.0
        YAML

        loader = described_class.new(config_path)
        expect(loader).to be_a(described_class)
      end

      it '全項目を指定した設定で読み込める' do
        write_config(<<~YAML)
          sites:
            test_site:
              name: "テストサイト"
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
              path_mapping:
                - pattern: '\?cmd=top'
                  path: 'index.html'
        YAML

        loader = described_class.new(config_path)
        site_config = loader.site('test_site')

        expect(site_config.name).to eq('テストサイト')
        expect(site_config.base_url).to eq('http://example.com/wolf.cgi')
        expect(site_config.encoding).to eq('Shift_JIS')
        expect(site_config.wait_time).to eq(2.0)
        expect(site_config.assets[:download]).to be true
        expect(site_config.link_rewrite[:enabled]).to be true
        expect(site_config.pages[:index]).to eq('?cmd=top')
        expect(site_config.path_mapping.length).to eq(1)
      end

      it 'デフォルト値が正しく適用される' do
        write_config(<<~YAML)
          sites:
            test_site:
              name: "テストサイト"
              base_url: "http://example.com/wolf.cgi"
              encoding: "UTF-8"
              wait_time: 1.0
        YAML

        loader = described_class.new(config_path)
        site_config = loader.site('test_site')

        # assets のデフォルト値
        expect(site_config.assets[:download]).to be true
        expect(site_config.assets[:types]).to eq(['css', 'js', 'images'])
        expect(site_config.assets[:css_dir]).to eq('assets/css')
        expect(site_config.assets[:js_dir]).to eq('assets/js')
        expect(site_config.assets[:images_dir]).to eq('assets/images')

        # link_rewrite のデフォルト値
        expect(site_config.link_rewrite[:enabled]).to be true
        expect(site_config.link_rewrite[:exclude_domains]).to eq([])
        expect(site_config.link_rewrite[:fallback]).to eq('#')

        # pages のデフォルト値
        expect(site_config.pages).to eq({})

        # path_mapping のデフォルト値
        expect(site_config.path_mapping).to eq([])
      end

      it '複数サイトの設定を読み込める' do
        write_config(<<~YAML)
          sites:
            site_a:
              name: "サイトA"
              base_url: "http://example.com/a/wolf.cgi"
              encoding: "UTF-8"
              wait_time: 1.0
            site_b:
              name: "サイトB"
              base_url: "http://example.com/b/wolf.cgi"
              encoding: "Shift_JIS"
              wait_time: 2.0
        YAML

        loader = described_class.new(config_path)

        expect(loader.site_names).to contain_exactly('site_a', 'site_b')

        site_a = loader.site('site_a')
        expect(site_a.name).to eq('サイトA')

        site_b = loader.site('site_b')
        expect(site_b.name).to eq('サイトB')
      end

      it '日本語のサイト名が扱える' do
        write_config(<<~YAML)
          sites:
            test_site:
              name: "人狼ゲームサイト"
              base_url: "http://example.com/wolf.cgi"
              encoding: "UTF-8"
              wait_time: 1.0
        YAML

        loader = described_class.new(config_path)
        site_config = loader.site('test_site')

        expect(site_config.name).to eq('人狼ゲームサイト')
      end
    end

    context '異常系' do
      it '設定ファイルが存在しない場合は ConfigError を発生させる' do
        non_existent_path = File.join(temp_dir, 'non_existent.yml')

        expect {
          described_class.new(non_existent_path)
        }.to raise_error(WolfArchiver::ConfigError, /設定ファイルが見つかりません/)
      end

      it 'YAMLパースエラーの場合は ConfigError を発生させる' do
        write_config(<<~YAML)
          sites:
            test_site:
              name: "テストサイト"
              base_url: "http://example.com/wolf.cgi"
              encoding: "UTF-8"
              wait_time: 1.0
            invalid: [unclosed
        YAML

        expect {
          described_class.new(config_path)
        }.to raise_error(WolfArchiver::ConfigError, /YAMLパースエラー/)
      end

      it 'sitesキーが存在しない場合は ConfigError を発生させる' do
        write_config(<<~YAML)
          other_key:
            test: "value"
        YAML

        expect {
          described_class.new(config_path)
        }.to raise_error(WolfArchiver::ConfigError, /sites キーが見つかりません/)
      end

      it '設定ファイルがハッシュでない場合は ConfigError を発生させる' do
        write_config(<<~YAML)
          - item1
          - item2
        YAML

        expect {
          described_class.new(config_path)
        }.to raise_error(WolfArchiver::ConfigError, /YAML ハッシュである必要があります/)
      end
    end
  end

  describe '#site' do
    let(:loader) do
      write_config(<<~YAML)
        sites:
          test_site:
            name: "テストサイト"
            base_url: "http://example.com/wolf.cgi"
            encoding: "UTF-8"
            wait_time: 1.0
      YAML
      described_class.new(config_path)
    end

    context '正常系' do
      it '指定されたサイトの設定を取得できる' do
        site_config = loader.site('test_site')

        expect(site_config).to be_a(WolfArchiver::SiteConfig)
        expect(site_config.name).to eq('テストサイト')
        expect(site_config.base_url).to eq('http://example.com/wolf.cgi')
        expect(site_config.encoding).to eq('UTF-8')
        expect(site_config.wait_time).to eq(1.0)
      end

      it 'シンボルでサイト名を指定しても取得できる' do
        site_config = loader.site(:test_site)

        expect(site_config).to be_a(WolfArchiver::SiteConfig)
        expect(site_config.name).to eq('テストサイト')
      end
    end

    context '異常系' do
      it '存在しないサイト名を指定した場合は ConfigError を発生させる' do
        expect {
          loader.site('non_existent_site')
        }.to raise_error(WolfArchiver::ConfigError, /サイト 'non_existent_site' が見つかりません/)
      end
    end
  end

  describe '#site_names' do
    it '全サイト名のリストを取得できる' do
      write_config(<<~YAML)
        sites:
          site_a:
            name: "サイトA"
            base_url: "http://example.com/a/wolf.cgi"
            encoding: "UTF-8"
            wait_time: 1.0
          site_b:
            name: "サイトB"
            base_url: "http://example.com/b/wolf.cgi"
            encoding: "UTF-8"
            wait_time: 1.0
          site_c:
            name: "サイトC"
            base_url: "http://example.com/c/wolf.cgi"
            encoding: "UTF-8"
            wait_time: 1.0
      YAML

      loader = described_class.new(config_path)

      expect(loader.site_names).to contain_exactly('site_a', 'site_b', 'site_c')
    end

    it 'サイトが存在しない場合は空配列を返す' do
      write_config(<<~YAML)
        sites: {}
      YAML

      loader = described_class.new(config_path)

      expect(loader.site_names).to eq([])
    end
  end
end

RSpec.describe WolfArchiver::SiteConfig do
  let(:temp_dir) { Dir.mktmpdir('wolf_archiver_test') }
  let(:config_path) { File.join(temp_dir, 'sites.yml') }

  after do
    FileUtils.rm_rf(temp_dir) if Dir.exist?(temp_dir)
  end

  def write_config(content)
    File.write(config_path, content)
  end

  describe '#localhost?' do
    it 'localhost の場合は true を返す' do
      write_config(<<~YAML)
        sites:
          test_site:
            name: "テストサイト"
            base_url: "http://localhost/wolf.cgi"
            encoding: "UTF-8"
            wait_time: 1.0
      YAML

      loader = WolfArchiver::ConfigLoader.new(config_path)
      site_config = loader.site('test_site')

      expect(site_config.localhost?).to be true
    end

    it '127.0.0.1 の場合は true を返す' do
      write_config(<<~YAML)
        sites:
          test_site:
            name: "テストサイト"
            base_url: "http://127.0.0.1/wolf.cgi"
            encoding: "UTF-8"
            wait_time: 1.0
      YAML

      loader = WolfArchiver::ConfigLoader.new(config_path)
      site_config = loader.site('test_site')

      expect(site_config.localhost?).to be true
    end

    it '外部URL の場合は false を返す' do
      write_config(<<~YAML)
        sites:
          test_site:
            name: "テストサイト"
            base_url: "http://example.com/wolf.cgi"
            encoding: "UTF-8"
            wait_time: 1.0
      YAML

      loader = WolfArchiver::ConfigLoader.new(config_path)
      site_config = loader.site('test_site')

      expect(site_config.localhost?).to be false
    end
  end

  describe '#actual_wait_time' do
    it 'localhost の場合は 0 を返す' do
      write_config(<<~YAML)
        sites:
          test_site:
            name: "テストサイト"
            base_url: "http://localhost/wolf.cgi"
            encoding: "UTF-8"
            wait_time: 2.5
      YAML

      loader = WolfArchiver::ConfigLoader.new(config_path)
      site_config = loader.site('test_site')

      expect(site_config.actual_wait_time).to eq(0)
    end

    it '外部URL の場合は wait_time を返す' do
      write_config(<<~YAML)
        sites:
          test_site:
            name: "テストサイト"
            base_url: "http://example.com/wolf.cgi"
            encoding: "UTF-8"
            wait_time: 2.5
      YAML

      loader = WolfArchiver::ConfigLoader.new(config_path)
      site_config = loader.site('test_site')

      expect(site_config.actual_wait_time).to eq(2.5)
    end
  end

  describe 'バリデーション' do
    context '必須項目チェック' do
      it 'name が欠落している場合は ConfigError を発生させる' do
        write_config(<<~YAML)
          sites:
            test_site:
              base_url: "http://example.com/wolf.cgi"
              encoding: "UTF-8"
              wait_time: 1.0
        YAML

        expect {
          loader = WolfArchiver::ConfigLoader.new(config_path)
          loader.site('test_site')
        }.to raise_error(WolfArchiver::ConfigError, /name が設定されていません/)
      end

      it 'base_url が欠落している場合は ConfigError を発生させる' do
        write_config(<<~YAML)
          sites:
            test_site:
              name: "テストサイト"
              encoding: "UTF-8"
              wait_time: 1.0
        YAML

        expect {
          loader = WolfArchiver::ConfigLoader.new(config_path)
          loader.site('test_site')
        }.to raise_error(WolfArchiver::ConfigError, /base_url が設定されていません/)
      end

      it 'encoding が欠落している場合は ConfigError を発生させる' do
        write_config(<<~YAML)
          sites:
            test_site:
              name: "テストサイト"
              base_url: "http://example.com/wolf.cgi"
              wait_time: 1.0
        YAML

        expect {
          loader = WolfArchiver::ConfigLoader.new(config_path)
          loader.site('test_site')
        }.to raise_error(WolfArchiver::ConfigError, /encoding が設定されていません/)
      end

      it 'wait_time が欠落している場合は ConfigError を発生させる' do
        write_config(<<~YAML)
          sites:
            test_site:
              name: "テストサイト"
              base_url: "http://example.com/wolf.cgi"
              encoding: "UTF-8"
        YAML

        expect {
          loader = WolfArchiver::ConfigLoader.new(config_path)
          loader.site('test_site')
        }.to raise_error(WolfArchiver::ConfigError, /wait_time が設定されていません/)
      end
    end

    context '値の範囲チェック' do
      it 'wait_time が負の数の場合は ConfigError を発生させる' do
        write_config(<<~YAML)
          sites:
            test_site:
              name: "テストサイト"
              base_url: "http://example.com/wolf.cgi"
              encoding: "UTF-8"
              wait_time: -1.0
        YAML

        expect {
          loader = WolfArchiver::ConfigLoader.new(config_path)
          loader.site('test_site')
        }.to raise_error(WolfArchiver::ConfigError, /wait_time は0以上である必要があります/)
      end
    end
  end
end

