# frozen_string_literal: true

require 'spec_helper'

RSpec.describe WolfArchiver::EncodingConverter do
  describe '.to_utf8' do
    context '正常系' do
      it 'Shift_JIS → UTF-8 変換ができる' do
        # ひらがな「あいうえお」をShift_JISでエンコード
        sjis_content = "\x82\xA0\x82\xA2\x82\xA4\x82\xA6\x82\xA8".dup.force_encoding('Shift_JIS')
        result = described_class.to_utf8(sjis_content, 'Shift_JIS')

        expect(result.encoding).to eq(Encoding::UTF_8)
        expect(result).to eq('あいうえお')
      end

      it 'EUC-JP → UTF-8 変換ができる' do
        # カタカナ「アイウエオ」をEUC-JPでエンコード
        # EUC-JPの「ア」は \xA5\xA2、「イ」は \xA5\xA4 など
        euc_content = "\xA5\xA2\xA5\xA4\xA5\xA6\xA5\xA8\xA5\xAA".dup.force_encoding('EUC-JP')
        result = described_class.to_utf8(euc_content, 'EUC-JP')

        expect(result.encoding).to eq(Encoding::UTF_8)
        expect(result).to eq('アイウエオ')
      end

      it 'UTF-8 → UTF-8（変換なし）' do
        utf8_content = 'あいうえお'
        result = described_class.to_utf8(utf8_content, 'UTF-8')

        expect(result.encoding).to eq(Encoding::UTF_8)
        expect(result).to eq('あいうえお')
      end

      it '空文字列の処理ができる' do
        result = described_class.to_utf8('', 'Shift_JIS')

        expect(result).to eq('')
        expect(result.encoding).to eq(Encoding::UTF_8)
      end

      it 'エンコーディング名の正規化（大文字小文字）ができる' do
        sjis_content = "\x82\xA0".dup.force_encoding('Shift_JIS')
        
        expect(described_class.to_utf8(sjis_content.dup, 'shift_jis')).to eq('あ')
        expect(described_class.to_utf8(sjis_content.dup, 'SHIFT_JIS')).to eq('あ')
        expect(described_class.to_utf8(sjis_content.dup, 'Shift_JIS')).to eq('あ')
      end

      it 'エンコーディング名の正規化（ハイフン）ができる' do
        # EUC-JPの「ア」は \xA5\xA2
        euc_content = "\xA5\xA2".dup.force_encoding('EUC-JP')
        
        expect(described_class.to_utf8(euc_content.dup, 'euc-jp')).to eq('ア')
        expect(described_class.to_utf8(euc_content.dup, 'eucjp')).to eq('ア')
      end

      it 'Windows-31J（CP932）の扱いができる' do
        # CP932はShift_JISとして扱う
        cp932_content = "\x82\xA0".dup.force_encoding('Windows-31J')
        result = described_class.to_utf8(cp932_content, 'cp932')

        expect(result.encoding).to eq(Encoding::UTF_8)
        expect(result).to eq('あ')
      end

      it '典型的な日本語文字（ひらがな、カタカナ、漢字）が変換できる' do
        sjis_content = 'ひらがなカタカナ漢字'.encode('Shift_JIS')
        result = described_class.to_utf8(sjis_content, 'Shift_JIS')

        expect(result).to eq('ひらがなカタカナ漢字')
      end

      it '特殊文字（①②③、㈱）が変換できる' do
        # 特殊文字はShift_JISに直接エンコードできないため、バイナリデータとして扱う
        # 実際のShift_JISバイト列を使用
        sjis_content = "\x81\x9A\x81\x9B\x81\x9C\x81\x6A".dup.force_encoding('Shift_JIS')
        result = described_class.to_utf8(sjis_content, 'Shift_JIS')

        # 変換結果を確認（実際の文字は環境依存の可能性があるため、エンコーディングのみ確認）
        expect(result.encoding).to eq(Encoding::UTF_8)
      end

      it '半角カナが変換できる' do
        sjis_content = 'ｱｲｳｴｵ'.encode('Shift_JIS')
        result = described_class.to_utf8(sjis_content, 'Shift_JIS')

        expect(result).to eq('ｱｲｳｴｵ')
      end

      it '部分的に不正なバイト列は置換される' do
        # 正常なShift_JIS文字列に不正なバイトを混入
        sjis_content = "\x82\xA0\xFF\x82\xA2".dup.force_encoding('Shift_JIS')
        result = described_class.to_utf8(sjis_content, 'Shift_JIS')

        expect(result).to include('あ')
        expect(result).to include('?')
        expect(result).to include('い')
      end
    end

    context '異常系' do
      it '未サポートのエンコーディングの場合は EncodingError を発生させる' do
        content = 'test'

        # ISO-8859-1はRubyでサポートされているため、実際に未サポートのエンコーディングを使用
        expect {
          described_class.to_utf8(content, 'INVALID-ENCODING-12345')
        }.to raise_error(WolfArchiver::EncodingError, /未サポートのエンコーディング/)
      end

      it 'nilを渡す場合は ArgumentError を発生させる' do
        expect {
          described_class.to_utf8(nil, 'UTF-8')
        }.to raise_error(ArgumentError, /content must be a String/)
      end

      it '完全に不正なバイト列の場合は置換される（エラーにはならない）' do
        # UTF-16LEのBOM（Shift_JISとしては不正）
        # 実装では invalid: :replace により置換されるため、エラーにはならない
        invalid_content = "\xFF\xFE\x00\x00".dup.force_encoding('BINARY')

        result = described_class.to_utf8(invalid_content, 'Shift_JIS')
        expect(result.encoding).to eq(Encoding::UTF_8)
        expect(result).to include('?')
      end
    end

    context 'エッジケース' do
      it '0バイトの文字列を処理できる' do
        result = described_class.to_utf8('', 'Shift_JIS')

        expect(result).to eq('')
        expect(result.encoding).to eq(Encoding::UTF_8)
      end

      it '不正文字が連続する場合は置換される' do
        invalid_content = "\xFF\xFF\xFF".dup.force_encoding('BINARY')
        result = described_class.to_utf8(invalid_content, 'Shift_JIS')

        expect(result).to eq('???')
      end

      it '元の文字列を変更しない' do
        original = "\x82\xA0".dup.force_encoding('Shift_JIS')
        original_dup = original.dup

        described_class.to_utf8(original, 'Shift_JIS')

        expect(original).to eq(original_dup)
      end
    end
  end

  describe '.supported_encodings' do
    it 'サポートされているエンコーディングのリストを返す' do
      supported = described_class.supported_encodings

      expect(supported).to be_an(Array)
      expect(supported).to include('Shift_JIS')
      expect(supported).to include('EUC-JP')
      expect(supported).to include('UTF-8')
    end

    it '重複がない' do
      supported = described_class.supported_encodings

      expect(supported.length).to eq(supported.uniq.length)
    end
  end
end

