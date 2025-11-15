# frozen_string_literal: true

require 'spec_helper'
require 'tempfile'
require 'fileutils'

RSpec.describe WolfArchiver::Storage do
  let(:temp_dir) { Dir.mktmpdir('wolf_archiver_test') }
  let(:base_dir) { File.join(temp_dir, 'archive', 'site_a') }
  let(:storage) { described_class.new(base_dir) }

  before do
    # テスト用のストレージを作成
    storage
  end

  after do
    FileUtils.rm_rf(temp_dir) if Dir.exist?(temp_dir)
  end

  describe '#initialize' do
    it 'base_dirを設定できる' do
      expect(storage).to be_a(described_class)
    end

    it 'base_dirが存在しない場合は作成する' do
      new_dir = File.join(temp_dir, 'new_dir')
      storage = described_class.new(new_dir)

      expect(Dir.exist?(new_dir)).to be true
    end
  end

  describe '#save' do
    context '正常系' do
      it '通常のファイル保存ができる' do
        content = '<html><body>Test</body></html>'
        path = storage.save('index.html', content)

        expect(File.exist?(path)).to be true
        expect(File.read(path)).to eq(content)
      end

      it 'ネストしたディレクトリでのファイル保存ができる' do
        content = '<html><body>Village</body></html>'
        path = storage.save('villages/1/day1.html', content)

        expect(File.exist?(path)).to be true
        expect(File.read(path)).to eq(content)
        expect(path).to include('villages/1/day1.html')
      end

      it '既存ファイルの上書きができる' do
        content1 = '<html>First</html>'
        content2 = '<html>Second</html>'

        storage.save('index.html', content1)
        storage.save('index.html', content2)

        expect(File.read(storage.absolute_path('index.html'))).to eq(content2)
      end

      it '空のコンテンツを保存できる' do
        path = storage.save('empty.html', '')

        expect(File.exist?(path)).to be true
        expect(File.read(path)).to eq('')
      end

      it 'エンコーディングを指定して保存できる' do
        content = 'テスト'
        path = storage.save('test.html', content, encoding: 'UTF-8')

        expect(File.read(path, encoding: 'UTF-8')).to eq(content)
      end
    end

    context '異常系' do
      it '不正なパス（..含む）の場合は StorageError を発生させる' do
        expect {
          storage.save('../../etc/passwd', 'hacked')
        }.to raise_error(WolfArchiver::StorageError, /不正なパス/)
      end

      it '空文字列のパスはエラーになる' do
        # 空文字列は正規化後も空になり、エラーになる
        expect {
          storage.save('', 'content')
        }.to raise_error(WolfArchiver::StorageError, /パスが空です/)
      end
    end

    context 'パス正規化' do
      it '先頭のスラッシュを除去する' do
        path1 = storage.save('/index.html', 'content')
        path2 = storage.save('index.html', 'content')

        expect(File.basename(path1)).to eq(File.basename(path2))
      end

      it '連続するスラッシュを単一に変換する' do
        path = storage.save('dir//subdir///file.html', 'content')

        expect(File.exist?(path)).to be true
        expect(path).not_to include('//')
      end
    end
  end

  describe '#save_binary' do
    context '正常系' do
      it 'バイナリファイル保存ができる' do
        binary_data = "\x89PNG\r\n\x1a\n".dup.force_encoding('BINARY')
        path = storage.save_binary('image.png', binary_data)

        expect(File.exist?(path)).to be true
        expect(File.binread(path)).to eq(binary_data)
      end

      it 'ネストしたディレクトリでのバイナリ保存ができる' do
        binary_data = 'binary content'.dup.force_encoding('BINARY')
        path = storage.save_binary('assets/images/icon.png', binary_data)

        expect(File.exist?(path)).to be true
        expect(path).to include('assets/images/icon.png')
      end
    end
  end

  describe '#exist?' do
    it '存在するファイルの場合は true を返す' do
      storage.save('test.html', 'content')

      expect(storage.exist?('test.html')).to be true
    end

    it '存在しないファイルの場合は false を返す' do
      expect(storage.exist?('nonexistent.html')).to be false
    end

    it 'ネストしたパスでも動作する' do
      storage.save('dir/subdir/file.html', 'content')

      expect(storage.exist?('dir/subdir/file.html')).to be true
      expect(storage.exist?('dir/subdir/nonexistent.html')).to be false
    end
  end

  describe '#read' do
    context '正常系' do
      it 'ファイルを読み込める' do
        content = '<html><body>Test</body></html>'
        storage.save('test.html', content)

        result = storage.read('test.html')

        expect(result).to eq(content)
      end

      it 'エンコーディングを指定して読み込める' do
        content = 'テスト'
        storage.save('test.html', content, encoding: 'UTF-8')

        result = storage.read('test.html', encoding: 'UTF-8')

        expect(result).to eq(content)
      end
    end

    context '異常系' do
      it '存在しないファイルの場合は nil を返す' do
        result = storage.read('nonexistent.html')

        expect(result).to be_nil
      end
    end
  end

  describe '#absolute_path' do
    it '絶対パスを取得できる' do
      path = storage.absolute_path('test.html')

      expect(Pathname.new(path).absolute?).to be true
      expect(path).to include('test.html')
      expect(path).to start_with(base_dir)
    end

    it 'ネストしたパスでも動作する' do
      path = storage.absolute_path('dir/subdir/file.html')

      expect(Pathname.new(path).absolute?).to be true
      expect(path).to include('dir/subdir/file.html')
    end
  end

  describe '#clear' do
    it 'base_dirを削除できる' do
      storage.save('test.html', 'content')
      expect(Dir.exist?(base_dir)).to be true

      storage.clear

      expect(Dir.exist?(base_dir)).to be false
    end

    it 'base_dirが存在しない場合でもエラーにならない' do
      storage.clear
      storage.clear # 2回目

      expect(Dir.exist?(base_dir)).to be false
    end
  end

  describe 'パストラバーサル対策' do
    it '../を含むパスを拒否する' do
      expect {
        storage.save('../outside.html', 'content')
      }.to raise_error(WolfArchiver::StorageError, /不正なパス/)
    end

    it '複数の../を含むパスを拒否する' do
      expect {
        storage.save('../../etc/passwd', 'content')
      }.to raise_error(WolfArchiver::StorageError, /不正なパス/)
    end

    it '..を含むパスはすべて拒否する' do
      # ファイル名に..が含まれる場合も拒否（セキュリティのため）
      expect {
        storage.save('file..name.html', 'content')
      }.to raise_error(WolfArchiver::StorageError, /不正なパス/)
    end
  end

  describe 'エッジケース' do
      it '長いファイル名でも動作する' do
        # Windowsのパス長制限を考慮して、適度な長さに制限
        long_name = 'a' * 100 + '.html'
        content = 'test'

        path = storage.save(long_name, content)

        expect(File.exist?(path)).to be true
      end

    it '日本語を含むファイル名でも動作する' do
      japanese_name = 'テスト.html'
      content = 'test'

      path = storage.save(japanese_name, content)

      expect(File.exist?(path)).to be true
      expect(storage.read(japanese_name)).to eq(content)
    end

    it '複数のファイルを同時に保存できる' do
      storage.save('file1.html', 'content1')
      storage.save('file2.html', 'content2')
      storage.save('dir/file3.html', 'content3')

      expect(storage.exist?('file1.html')).to be true
      expect(storage.exist?('file2.html')).to be true
      expect(storage.exist?('dir/file3.html')).to be true
    end
  end
end

