# Storage - ファイルシステム管理
# 詳細仕様: spec/storage_spec.md を参照

module WolfArchiver
  class Storage
    def initialize(base_dir)
      @base_dir = base_dir
      @created_dirs = Set.new
      FileUtils.mkdir_p(@base_dir) unless Dir.exist?(@base_dir)
    end

    def save(relative_path, content, encoding: 'UTF-8')
      path = normalize_path(relative_path)
      full_path = File.join(@base_dir, path)
      
      ensure_directory(full_path)
      File.write(full_path, content, encoding: encoding)
      
      full_path
    rescue Errno::EACCES => e
      raise StorageError, "書き込み権限がありません: #{path}"
    rescue Errno::ENOSPC => e
      raise StorageError, "ディスク容量が不足しています: #{path}"
    rescue => e
      raise StorageError, "保存失敗: #{e.message}"
    end

    def save_binary(relative_path, content)
      path = normalize_path(relative_path)
      full_path = File.join(@base_dir, path)
      
      ensure_directory(full_path)
      File.binwrite(full_path, content)
      
      full_path
    rescue => e
      raise StorageError, "バイナリ保存失敗: #{e.message}"
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
      
      File.read(full_path, encoding: encoding)
    rescue => e
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
end
