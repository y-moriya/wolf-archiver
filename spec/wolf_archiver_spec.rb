require 'spec_helper'

RSpec.describe WolfArchiver::WolfArchiver do
  let(:site_name) { 'test_site' }
  let(:config_path) { 'config/sites.yml' }
  let(:output_dir) { 'tmp/test_archive' }

  let(:config_loader) { instance_double(WolfArchiver::ConfigLoader) }
  let(:site_config) { double('SiteConfig') }
  let(:storage) { instance_double(WolfArchiver::Storage) }
  let(:rate_limiter) { instance_double(WolfArchiver::RateLimiter) }
  let(:fetcher) { instance_double(WolfArchiver::Fetcher) }
  let(:parser) { instance_double(WolfArchiver::Parser) }
  let(:path_mapper) { instance_double(WolfArchiver::PathMapper) }
  let(:asset_downloader) { instance_double(WolfArchiver::AssetDownloader) }
  let(:link_rewriter) { instance_double(WolfArchiver::LinkRewriter) }

  let(:base_url) { 'http://example.com/wolf.cgi' }
  let(:pages_config) do
    {
      index: '?cmd=top',
      village_list: '?cmd=vlist',
      village: '?cmd=vlog&vil=%{village_id}&turn=%{date}',
      user_list: '?cmd=ulist',
      user: '?cmd=ulog&uid=%{user_id}',
      static: ['?cmd=rule']
    }
  end

  before do
    # Mock ConfigLoader
    allow(WolfArchiver::ConfigLoader).to receive(:new).and_return(config_loader)
    allow(config_loader).to receive(:site).with(site_name).and_return(site_config)

    # Mock SiteConfig
    allow(site_config).to receive(:name).and_return('Test Site')
    allow(site_config).to receive(:base_url).and_return(base_url)
    allow(site_config).to receive(:encoding).and_return('Shift_JIS')
    allow(site_config).to receive(:actual_wait_time).and_return(1.0)
    allow(site_config).to receive(:localhost?).and_return(false)
    allow(site_config).to receive(:path_mapping).and_return([])
    allow(site_config).to receive(:assets).and_return({ download: true })
    allow(site_config).to receive(:pages).and_return(pages_config)

    # Mock other dependencies
    allow(WolfArchiver::Storage).to receive(:new).and_return(storage)
    allow(WolfArchiver::RateLimiter).to receive(:new).and_return(rate_limiter)
    allow(WolfArchiver::Fetcher).to receive(:new).and_return(fetcher)
    allow(WolfArchiver::Parser).to receive(:new).and_return(parser)
    allow(WolfArchiver::PathMapper).to receive(:new).and_return(path_mapper)
    allow(WolfArchiver::AssetDownloader).to receive(:new).and_return(asset_downloader)
    allow(WolfArchiver::LinkRewriter).to receive(:new).and_return(link_rewriter)

    # Suppress stdout during tests
    allow($stdout).to receive(:puts)
  end

  subject { described_class.new(site_name: site_name, config_path: config_path, output_dir: output_dir) }

  describe '#initialize' do
    it 'initializes all modules' do
      subject # インスタンスを作成

      expect(WolfArchiver::ConfigLoader).to have_received(:new).with(config_path)
      expect(WolfArchiver::Storage).to have_received(:new).with(File.join(output_dir, site_name))
      expect(WolfArchiver::RateLimiter).to have_received(:new).with(1.0, enabled: true)
      expect(WolfArchiver::Fetcher).to have_received(:new).with(base_url, rate_limiter, timeout: 30)
      expect(WolfArchiver::Parser).to have_received(:new).with(base_url)
      expect(WolfArchiver::PathMapper).to have_received(:new).with(base_url, [])
      expect(WolfArchiver::AssetDownloader).to have_received(:new).with(fetcher, storage, path_mapper)
    end
  end

  describe '#run' do
    let(:fetch_result) { double('FetchResult', success?: true, body: 'html content', status: 200) }
    let(:parse_result) { double('ParseResult', links: [], assets: []) }
    let(:download_result) { double('DownloadResult', total: 0, succeeded: [], failed: [], skipped: []) }

    before do
      allow(fetcher).to receive(:fetch).and_return(fetch_result)
      allow(WolfArchiver::EncodingConverter).to receive(:to_utf8) { |body, _| body }
      allow(parser).to receive(:parse).and_return(parse_result)
      allow(asset_downloader).to receive(:download).and_return(download_result)
      allow(link_rewriter).to receive(:rewrite).and_return('rewritten html')
      allow(storage).to receive(:exist?).and_return(false)
      allow(storage).to receive(:save)
      allow(path_mapper).to receive(:url_to_path).and_return(nil)
    end

    context 'with default options' do
      it 'processes index page and static pages' do
        result = subject.run

        # Index page
        expect(fetcher).to have_received(:fetch).with("#{base_url}?cmd=top")
        expect(storage).to have_received(:save).with('index.html', 'rewritten html')

        # Static page
        expect(fetcher).to have_received(:fetch).with("#{base_url}?cmd=rule")
        expect(storage).to have_received(:save).with('static/rule.html', 'rewritten html')

        expect(result).to be_a(WolfArchiver::ArchiveResult)
        expect(result.total_pages).to eq(2)
      end
    end

    context 'with village_ids option' do
      it 'processes village pages' do
        # Mock day range detection fetch (turn=0)
        day_range_html = <<~HTML
          <html>
            <body>
              <a href="?cmd=vlog&vil=1&turn=1">Day 1</a>
              <a href="?cmd=vlog&vil=1&turn=5">Day 5</a>
            </body>
          </html>
        HTML
        allow(fetcher).to receive(:fetch).with("#{base_url}?cmd=vlog&vil=1&turn=0")
                                         .and_return(double(success?: true, body: day_range_html, status: 200))

        subject.run(village_ids: [1])

        # Village list
        expect(fetcher).to have_received(:fetch).with("#{base_url}?cmd=vlist")

        # Day range detection
        # Village pages (0..5 days)
        (0..5).each do |day|
          if day == 0
            expect(fetcher).to have_received(:fetch).with("#{base_url}?cmd=vlog&vil=1&turn=#{day}").twice
          else
            expect(fetcher).to have_received(:fetch).with("#{base_url}?cmd=vlog&vil=1&turn=#{day}")
          end
          expect(storage).to have_received(:save).with("villages/1/day#{day}.html", 'rewritten html')
        end
      end
    end

    context 'with user_ids option' do
      it 'processes user pages' do
        subject.run(user_ids: [100])

        # User list
        expect(fetcher).to have_received(:fetch).with("#{base_url}?cmd=ulist")

        # User page
        expect(fetcher).to have_received(:fetch).with("#{base_url}?cmd=ulog&uid=100")
        expect(storage).to have_received(:save).with('users/100.html', 'rewritten html')
      end
    end

    context 'when page already exists' do
      before do
        allow(storage).to receive(:exist?).with('index.html').and_return(true)
      end

      it 'skips processing for that page' do
        subject.run

        expect(fetcher).not_to have_received(:fetch).with("#{base_url}?cmd=top")
        expect(storage).not_to have_received(:save).with('index.html', any_args)
      end
    end

    context 'when fetch fails' do
      let(:error_result) { double('FetchResult', success?: false, status: 404) }

      before do
        allow(fetcher).to receive(:fetch).with("#{base_url}?cmd=top").and_return(error_result)
      end

      it 'counts as failure and continues' do
        result = subject.run

        expect(result.failed_pages).to eq(1) # index.html failed
        expect(result.succeeded_pages).to eq(1) # static/rule.html succeeded
      end
    end

    context 'when asset download is enabled' do
      let(:assets) { [double('Asset')] }
      let(:parse_result) { double('ParseResult', links: [], assets: assets) }

      before do
        allow(parser).to receive(:parse).and_return(parse_result)
      end

      it 'downloads assets' do
        subject.run

        expect(asset_downloader).to have_received(:download).with(assets).at_least(:once)
      end
    end

    describe '#discover_village_ids' do
      let(:village_list_html) do
        <<~HTML
          <html>
            <body>
              <a href="?cmd=vlog&vid=1&turn=0">Village 1</a>
              <a href="?cmd=vlog&vid=2&turn=0">Village 2</a>
              <a href="?cmd=other">Other Link</a>
              <a href="?vid=3&cmd=vlog">Village 3</a>
            </body>
          </html>
        HTML
      end

      before do
        allow(fetcher).to receive(:fetch).with("#{base_url}?cmd=vlist")
                                         .and_return(double(success?: true, body: village_list_html, status: 200))
      end

      it 'extracts village IDs from links' do
        ids = subject.send(:discover_village_ids)
        expect(ids).to eq([1, 2, 3])
      end
    end
  end
end
