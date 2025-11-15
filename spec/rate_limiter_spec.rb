# frozen_string_literal: true

require 'spec_helper'

RSpec.describe WolfArchiver::RateLimiter do
  describe '#initialize' do
    it 'wait_timeとenabledを設定できる' do
      limiter = described_class.new(2.0, enabled: true)

      expect(limiter.enabled?).to be true
    end

    it 'enabled: false の場合は無効化される' do
      limiter = described_class.new(2.0, enabled: false)

      expect(limiter.enabled?).to be false
    end

    it 'wait_time = 0 の場合は自動的に無効化される' do
      limiter = described_class.new(0)

      expect(limiter.enabled?).to be false
    end
  end

  describe '#wait' do
    context '正常系' do
      it '初回リクエストは待機なし' do
        limiter = described_class.new(2.0)

        start_time = Time.now
        limiter.wait
        elapsed = Time.now - start_time

        expect(elapsed).to be < 0.1 # 100ms以内
      end

      it '2回目のリクエストは適切に待機する' do
        limiter = described_class.new(0.2) # 200ms待機

        # 1回目（待機なし）
        limiter.wait

        # 2回目（待機あり）
        start_time = Time.now
        limiter.wait
        elapsed = Time.now - start_time

        expect(elapsed).to be >= 0.18 # 180ms以上（誤差考慮）
        expect(elapsed).to be < 0.3   # 300ms以内
      end

      it '十分な時間が経過していれば待機なし' do
        limiter = described_class.new(0.1)

        # 1回目
        limiter.wait

        # 十分な時間待機
        sleep(0.2)

        # 2回目（待機なし）
        start_time = Time.now
        limiter.wait
        elapsed = Time.now - start_time

        expect(elapsed).to be < 0.1
      end

      it 'wait_time = 0 の場合は常に待機なし' do
        limiter = described_class.new(0)

        start_time = Time.now
        limiter.wait
        limiter.wait
        elapsed = Time.now - start_time

        expect(elapsed).to be < 0.1
      end

      it 'enabled: false の場合は常に待機なし' do
        limiter = described_class.new(2.0, enabled: false)

        start_time = Time.now
        limiter.wait
        limiter.wait
        elapsed = Time.now - start_time

        expect(elapsed).to be < 0.1
      end
    end

    context 'タイミング精度' do
      it '待機時間の誤差が±100ms以内' do
        limiter = described_class.new(0.2)

        limiter.wait

        start_time = Time.now
        limiter.wait
        elapsed = Time.now - start_time

        expect(elapsed).to be >= 0.1  # 200ms - 100ms
        expect(elapsed).to be < 0.3   # 200ms + 100ms
      end

      it '連続リクエスト時の間隔が wait_time ± 100ms 以内' do
        wait_time = 0.2
        limiter = described_class.new(wait_time)

        times = []
        3.times do
          limiter.wait
          times << Time.now
        end

        # 2回目と3回目の間隔を確認
        interval = times[2] - times[1]

        expect(interval).to be >= wait_time - 0.1
        expect(interval).to be < wait_time + 0.1
      end
    end

    context 'エッジケース' do
      it '非常に小さいwait_time（0.01秒）でも動作する' do
        limiter = described_class.new(0.01)

        limiter.wait

        start_time = Time.now
        limiter.wait
        elapsed = Time.now - start_time

        # 精度の問題で0になる可能性もあるが、エラーにならないことを確認
        expect(elapsed).to be >= 0
        expect(elapsed).to be < 0.1
      end

      it 'リセット後は初回リクエスト扱い' do
        limiter = described_class.new(0.2)

        limiter.wait
        limiter.reset

        # リセット後は待機なし
        start_time = Time.now
        limiter.wait
        elapsed = Time.now - start_time

        expect(elapsed).to be < 0.1
      end
    end
  end

  describe '#elapsed_time' do
    it '初回は無限大を返す' do
      limiter = described_class.new(2.0)

      expect(limiter.elapsed_time).to eq(Float::INFINITY)
    end

    it '経過時間が正しく計算される' do
      limiter = described_class.new(2.0)

      limiter.wait
      sleep(0.1)

      elapsed = limiter.elapsed_time
      expect(elapsed).to be >= 0.09
      expect(elapsed).to be < 0.2
    end
  end

  describe '#remaining_wait_time' do
    it '初回は0を返す' do
      limiter = described_class.new(2.0)

      expect(limiter.remaining_wait_time).to eq(0)
    end

    it '待機が必要な場合は残り時間を返す' do
      limiter = described_class.new(0.2)

      limiter.wait
      # すぐに確認すると残り時間がある
      remaining = limiter.remaining_wait_time

      expect(remaining).to be > 0
      expect(remaining).to be <= 0.2
    end

    it '待機不要な場合は0を返す' do
      limiter = described_class.new(0.1)

      limiter.wait
      sleep(0.2)

      expect(limiter.remaining_wait_time).to eq(0)
    end

    it 'enabled: false の場合は常に0を返す' do
      limiter = described_class.new(2.0, enabled: false)

      limiter.wait

      expect(limiter.remaining_wait_time).to eq(0)
    end
  end

  describe '#enabled?' do
    it '有効な場合は true を返す' do
      limiter = described_class.new(2.0, enabled: true)

      expect(limiter.enabled?).to be true
    end

    it '無効な場合は false を返す' do
      limiter = described_class.new(2.0, enabled: false)

      expect(limiter.enabled?).to be false
    end

    it 'wait_time = 0 の場合は false を返す' do
      limiter = described_class.new(0)

      expect(limiter.enabled?).to be false
    end
  end

  describe '#reset' do
    it 'last_request_timeをリセットする' do
      limiter = described_class.new(2.0)

      limiter.wait
      expect(limiter.elapsed_time).not_to eq(Float::INFINITY)

      limiter.reset
      expect(limiter.elapsed_time).to eq(Float::INFINITY)
    end

    it 'リセット後は初回リクエスト扱いになる' do
      limiter = described_class.new(0.2)

      limiter.wait
      limiter.reset

      expect(limiter.remaining_wait_time).to eq(0)
    end
  end
end

