# WolfArchiver - CGIベースの人狼ゲームサイトアーカイバー
# @author wellk
# @version 1.0.0

require 'logger'
require 'set'
require 'uri'
require 'pathname'
require 'fileutils'
require 'time'

# Main module
module WolfArchiver
  VERSION = '1.0.0'

  # 各モジュールを読み込む
  autoload :LoggerConfig,       'wolf_archiver/logger_config'
  autoload :ConfigLoader,       'wolf_archiver/config_loader'
  autoload :EncodingConverter,  'wolf_archiver/encoding_converter'
  autoload :RateLimiter,        'wolf_archiver/rate_limiter'
  autoload :Fetcher,            'wolf_archiver/fetcher'
  autoload :Parser,             'wolf_archiver/parser'
  autoload :Storage,            'wolf_archiver/storage'
  autoload :PathMapper,         'wolf_archiver/path_mapper'
  autoload :LinkRewriter,       'wolf_archiver/link_rewriter'
  autoload :AssetDownloader,    'wolf_archiver/asset_downloader'
  autoload :WolfArchiver,       'wolf_archiver/wolf_archiver'
  autoload :WolfArchiverCLI,    'wolf_archiver/cli'

  # エラークラス
  class WolfArchiverError < StandardError; end
  class ConfigError < WolfArchiverError; end
  class EncodingError < WolfArchiverError; end
  class FetchError < WolfArchiverError; end
  class ParserError < WolfArchiverError; end
  class StorageError < WolfArchiverError; end
  class PathMapperError < WolfArchiverError; end
  class LinkRewriterError < WolfArchiverError; end
  class AssetDownloaderError < WolfArchiverError; end
end
