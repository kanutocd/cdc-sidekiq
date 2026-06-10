# frozen_string_literal: true

require "test_helper"
require "support/fixtures"

class RuntimeTest < Minitest::Test
  def test_direct_runtime_processes_one_item
    processor = RecordingProcessor.new
    runtime = build_runtime(processor:, runtime: :direct)

    result = runtime.process("a")

    assert_equal "a", result.value
    assert_equal ["a"], processor.items
  end

  def test_direct_runtime_processes_many_items
    processor = RecordingProcessor.new
    runtime = build_runtime(processor:, runtime: :direct)

    results = runtime.process_many(%w[a b])

    assert_equal %w[a b], results.map(&:value)
    assert_predicate results, :frozen?
  end

  def test_direct_runtime_accepts_string_runtime_name
    processor = RecordingProcessor.new
    runtime = build_runtime(processor:, runtime: "direct")

    result = runtime.process("a")

    assert_equal "a", result.value
  end

  def test_unsupported_runtime_raises_for_process
    runtime = build_runtime(processor: RecordingProcessor.new, runtime: :bogus)

    assert_raises(CDC::Sidekiq::UnsupportedRuntimeError) do
      runtime.process("a")
    end
  end

  def test_unsupported_runtime_raises_for_process_many
    runtime = build_runtime(processor: RecordingProcessor.new, runtime: :bogus)

    assert_raises(CDC::Sidekiq::UnsupportedRuntimeError) do
      runtime.process_many(%w[a b])
    end
  end

  def test_runtime_shuts_down_pool_when_supported
    pool = ShutdownAwarePool.new
    runtime = RuntimeWithInjectedPool.new(pool)

    result = runtime.process("a")

    assert_equal "processed-a", result
    assert_equal ["a"], pool.items
    assert_equal 1, pool.shutdown_count
  end

  def test_runtime_shuts_down_pool_when_processing_raises
    pool = ShutdownAwarePool.new(raise_on_process: true)
    runtime = RuntimeWithInjectedPool.new(pool)

    assert_raises(RuntimeError) do
      runtime.process("a")
    end

    assert_equal 1, pool.shutdown_count
  end

  def test_runtime_does_not_attempt_shutdown_when_pool_build_fails
    runtime = RuntimeWithFailingPoolBuild.new

    error = assert_raises(RuntimeError) do
      runtime.process("a")
    end

    assert_equal "pool build failed", error.message
  end

  private

  def build_runtime(processor:, runtime:)
    CDC::Sidekiq::Runtime.new(
      processor:,
      runtime:,
      parallel_size: 1,
      concurrency: 1,
      timeout: nil,
      preserve_order: true
    )
  end
end

class ShutdownAwarePool
  attr_reader :items, :shutdown_count

  def initialize(raise_on_process: false)
    @raise_on_process = raise_on_process
    @items = []
    @shutdown_count = 0
  end

  def process(item)
    @items << item
    raise "boom" if @raise_on_process

    "processed-#{item}"
  end

  def shutdown
    @shutdown_count += 1
  end
end

class RuntimeWithInjectedPool < CDC::Sidekiq::Runtime
  def initialize(pool)
    @pool = pool
    super(
      processor: RecordingProcessor.new,
      runtime: :direct,
      parallel_size: 1,
      concurrency: 1,
      timeout: nil,
      preserve_order: true
    )
  end

  private

  def build_pool
    @pool
  end
end

class RuntimeWithFailingPoolBuild < CDC::Sidekiq::Runtime
  def initialize
    super(
      processor: RecordingProcessor.new,
      runtime: :direct,
      parallel_size: 1,
      concurrency: 1,
      timeout: nil,
      preserve_order: true
    )
  end

  private

  def build_pool
    raise "pool build failed"
  end
end
