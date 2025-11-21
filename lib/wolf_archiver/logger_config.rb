# LoggerConfig - ログ設定管理
# 日付ごとのログファイル出力とログレベル制御を提供

module WolfArchiver
  module LoggerConfig
    class << self
      # ロガーインスタンスを取得
      # @param name [String] ロガー名（通常はクラス名）
      # @return [Logger] ロガーインスタンス
      def logger(name = 'WolfArchiver')
        @loggers ||= {}
        @loggers[name] ||= create_logger(name)
      end

      private

      # ロガーインスタンスを作成
      def create_logger(name)
        ensure_log_directory

        logger = Logger.new(MultiIO.new(STDOUT, File.open(log_file, 'a')))
        logger.level = log_level
        logger.progname = name
        logger.formatter = proc do |severity, datetime, progname, msg|
          "[#{datetime.strftime('%Y-%m-%d %H:%M:%S')}] #{severity.ljust(5)} [#{progname}] #{msg}\n"
        end

        logger
      end

      # ログディレクトリを作成
      def ensure_log_directory
        log_dir = File.join(Dir.pwd, 'logs')
        FileUtils.mkdir_p(log_dir) unless Dir.exist?(log_dir)
      end

      # ログファイルパスを取得（日付ごと）
      def log_file
        log_dir = File.join(Dir.pwd, 'logs')
        date_str = Time.now.strftime('%Y-%m-%d')
        File.join(log_dir, "wolf_archiver_#{date_str}.log")
      end

      # 環境変数からログレベルを取得
      def log_level
        level_str = ENV['WOLF_ARCHIVER_LOG_LEVEL'] || 'NONE'
        case level_str.upcase
        when 'DEBUG'
          Logger::DEBUG
        when 'INFO'
          Logger::INFO
        when 'WARN'
          Logger::WARN
        when 'ERROR'
          Logger::ERROR
        when 'NONE'
          Logger::UNKNOWN + 1
        else
          Logger::UNKNOWN + 1
        end
      end
    end

    # 複数のIOに同時に出力するクラス
    class MultiIO
      def initialize(*targets)
        @targets = targets
      end

      def write(*args)
        @targets.each { |t| t.write(*args) }
      end

      def close
        @targets.each(&:close)
      end
    end
  end
end
