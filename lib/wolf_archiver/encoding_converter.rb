# EncodingConverter - 文字エンコーディング変換
# 詳細仕様: spec/encoding_converter_spec.md を参照

module WolfArchiver
  class EncodingConverter
    SUPPORTED_ENCODINGS = {
      'shift_jis' => 'Shift_JIS',
      'shiftjis' => 'Shift_JIS',
      'sjis' => 'Shift_JIS',
      'cp932' => 'Shift_JIS',
      'windows-31j' => 'Shift_JIS',
      'euc-jp' => 'EUC-JP',
      'eucjp' => 'EUC-JP',
      'utf-8' => 'UTF-8',
      'utf8' => 'UTF-8'
    }.freeze

    def self.to_utf8(content, from_encoding)
      raise ArgumentError, 'content must be a String' unless content.is_a?(String)
      
      normalized_encoding = normalize_encoding(from_encoding)
      validate_encoding(normalized_encoding)
      
      return content.dup.force_encoding('UTF-8') if normalized_encoding == 'UTF-8'
      
      content.dup.force_encoding(normalized_encoding)
             .encode('UTF-8', 
                     invalid: :replace,
                     undef: :replace,
                     replace: '?')
    rescue Encoding::InvalidByteSequenceError, Encoding::UndefinedConversionError => e
      raise EncodingError, "エンコーディング変換に失敗しました: #{e.message}"
    end

    def self.supported_encodings
      SUPPORTED_ENCODINGS.values.uniq
    end

    private

    def self.normalize_encoding(encoding)
      normalized = encoding.to_s.downcase.gsub(/[-_]/, '')
      SUPPORTED_ENCODINGS[normalized] || encoding
    end

    def self.validate_encoding(encoding)
      Encoding.find(encoding)
    rescue ArgumentError
      raise EncodingError, "未サポートのエンコーディング: #{encoding}"
    end
  end
end
