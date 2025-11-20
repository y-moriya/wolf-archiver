# Storage - ファイルシステム管理
# 詳細仕様: spec/storage_spec.md を参照

module WolfArchiver
  class Storage
    def initialize(base_dir)
      @logger = LoggerConfig.logger('Storage')
      @base_dir = base_dir
      @created_dirs = Set.new
      FileUtils.mkdir_p(@base_dir) unless Dir.exist?(@base_dir)
      @logger.info("Storage初期化: base_dir=#{base_dir}")
    end

    def save(relative_path, content, encoding: 'UTF-8')
      path = normalize_path(relative_path)
      raise StorageError.new("パスが空です", path: relative_path) if path.empty?
      
      full_path = File.join(@base_dir, path)
      @logger.debug("ファイル保存開始: #{path}")
      
      ensure_directory(full_path)
      File.write(full_path, content, encoding: encoding)
      @logger.debug("ファイル保存完了: #{path} (#{content.bytesize} bytes)")
      
      full_path
    rescue Errno::EACCES => e
      @logger.error("書き込み権限エラー: #{path}")
      raise StorageError.new("書き込み権限がありません: #{path}", path: path, original_error: e)
    rescue Errno::ENOSPC => e
      @logger.error("ディスク容量不足: #{path}")
      raise StorageError.new("ディスク容量が不足しています: #{path}", path: path, original_error: e)
    rescue => e
      @logger.error("保存失敗: #{path} - #{e.message}")
      raise StorageError.new("保存失敗: #{e.message}", path: path, original_error: e)
    end

    def save_binary(relative_path, content)
      path = normalize_path(relative_path)
      raise StorageError.new("パスが空です", path: relative_path) if path.empty?
      
      full_path = File.join(@base_dir, path)
      @logger.debug("バイナリ保存開始: #{path}")
      
      ensure_directory(full_path)
      File.binwrite(full_path, content)
      @logger.debug("バイナリ保存完了: #{path} (#{content.bytesize} bytes)")
      
      full_path
    rescue => e
      @logger.error("バイナリ保存失敗: #{path} - #{e.message}")
      raise StorageError.new("バイナリ保存失敗: #{e.message}", path: path, original_error: e)
    end

    def exist?(relative_path)
      path = normalize_path(relative_path)
      full_path = File.join(@base_dir, path)
      File.exist?(full_path)
    end

    def read(relative_path, encoding: 'UTF-8')
      path = normalize_path(relative_path)
      full_path = File.join(@base_dir, path)
      
      return nil unless File.exist?(full_path)
      
      if encoding == 'BINARY' || encoding == Encoding::BINARY
        File.binread(full_path)
      else
        File.read(full_path, encoding: encoding)
      end
    rescue => _e
      nil
    end

    def absolute_path(relative_path)
      File.join(@base_dir, normalize_path(relative_path))
    end

    def clear
      FileUtils.rm_rf(@base_dir) if Dir.exist?(@base_dir)
    end

    private

    def normalize_path(path)
      normalized = path.sub(/\A\/+/, '')
      normalized = normalized.gsub(/\/+/, '/')
      
      if normalized.include?('..')
        raise StorageError, "不正なパス: #{path}"
      end
      
      normalized
    end

    def ensure_directory(full_path)
      dir = File.dirname(full_path)
      return if @created_dirs.include?(dir)
      
      FileUtils.mkdir_p(dir) unless Dir.exist?(dir)
      @created_dirs.add(dir)
    end
  end

  class StorageError < WolfArchiverError
    attr_reader :path, :original_error

    def initialize(message, path: nil, original_error: nil)
      @path = path
      @original_error = original_error
      super(message)
    end
  end
end
