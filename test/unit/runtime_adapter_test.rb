# frozen_string_literal: true

require "test_helper"
require "support/fixtures"

class RuntimeAdapterTest < Minitest::Test
  def test_parallel_runtime_passes_configuration_to_cdc_parallel_pool
    install_fake_runtime("parallel", <<~RUBY)
      module CDC
        module Parallel
          class ProcessorPool
            def self.last_options = @last_options
            def initialize(processor:, size:, timeout:)
              @processor = processor
              @size = size
              @timeout = timeout
              self.class.instance_variable_set(:@last_options, { processor: processor, size: size, timeout: timeout })
            end
            def process_many(items) = items.map { |item| @processor.process(item) }.freeze
            def shutdown = (@shutdown = true)
          end
        end
      end
    RUBY

    processor = RecordingProcessor.new
    runtime = CDC::Sidekiq::Runtime.new(
      processor:,
      runtime: :parallel,
      parallel_size: 3,
      concurrency: 10,
      timeout: 1.5,
      preserve_order: true
    )

    results = runtime.process_many(%w[a b])

    assert_equal %w[a b], results.map(&:value)
    assert_equal({ processor: processor, size: 3, timeout: 1.5 }, CDC::Parallel::ProcessorPool.last_options)
  end

  def test_concurrent_runtime_passes_configuration_to_cdc_concurrent_pool
    install_fake_runtime("concurrent", <<~RUBY)
      module CDC
        module Concurrent
          class ProcessorPool
            def self.last_options = @last_options
            def initialize(processor:, concurrency:, timeout:, preserve_order:)
              @processor = processor
              self.class.instance_variable_set(
                :@last_options,
                { processor: processor, concurrency: concurrency, timeout: timeout, preserve_order: preserve_order }
              )
            end
            def process(item) = @processor.process(item)
            def shutdown = (@shutdown = true)
          end
        end
      end
    RUBY

    processor = RecordingProcessor.new
    runtime = CDC::Sidekiq::Runtime.new(
      processor:,
      runtime: :concurrent,
      parallel_size: 3,
      concurrency: 77,
      timeout: 2.5,
      preserve_order: false
    )

    result = runtime.process("a")

    assert_equal "a", result.value
    assert_equal(
      { processor: processor, concurrency: 77, timeout: 2.5, preserve_order: false },
      CDC::Concurrent::ProcessorPool.last_options
    )
  end

  private

  def install_fake_runtime(name, source)
    dir = File.join(Dir.pwd, "tmp", "fake_#{name}_runtime")
    FileUtils.mkdir_p(File.join(dir, "cdc"))
    File.write(File.join(dir, "cdc", "#{name}.rb"), source)
    $LOAD_PATH.unshift(dir) unless $LOAD_PATH.include?(dir)
  end
end
