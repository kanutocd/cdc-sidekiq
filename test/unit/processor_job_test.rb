# frozen_string_literal: true

require "test_helper"
require "support/fixtures"

class ProcessorJobTest < Minitest::Test
  def setup
    CDC::Sidekiq.reset_configuration!
  end

  def test_processes_array_payloads_with_process_many_by_default
    processor = RecordingProcessor.new
    job_class = Class.new do
      include CDC::Sidekiq::ProcessorJob
      cdc_runtime :direct
      cdc_processor processor
    end

    results = job_class.new.perform(%w[a b c])

    assert_equal %w[a b c], processor.items
    assert_equal %w[a b c], results.map(&:value)
    assert_predicate results, :frozen?
  end

  def test_can_process_array_payload_as_one_item
    processor = RecordingProcessor.new
    job_class = Class.new do
      include CDC::Sidekiq::ProcessorJob
      cdc_runtime :direct
      cdc_processor processor
      cdc_batch_payloads false
    end

    result = job_class.new.perform(%w[a b])

    assert_equal [%w[a b]], processor.items
    assert_equal %w[a b], result.value
  end

  def test_global_batch_payloads_false_processes_array_as_one_item
    CDC::Sidekiq.configure { |config| config.batch_payloads = false }
    processor = RecordingProcessor.new
    job_class = Class.new do
      include CDC::Sidekiq::ProcessorJob
      cdc_runtime :direct
      cdc_processor processor
    end

    result = job_class.new.perform(%w[a b])

    assert_equal [%w[a b]], processor.items
    assert_equal %w[a b], result.value
  end

  def test_raises_when_processor_is_missing
    job_class = Class.new do
      include CDC::Sidekiq::ProcessorJob
      cdc_runtime :direct
    end

    error = assert_raises(CDC::Sidekiq::MissingProcessorError) do
      job_class.new.perform("item")
    end

    assert_match(/must declare cdc_processor/, error.message)
  end

  def test_failed_results_raise_for_sidekiq_retry_by_default
    job_class = Class.new do
      include CDC::Sidekiq::ProcessorJob
      cdc_runtime :direct
      cdc_processor FailingProcessor
    end

    error = assert_raises(CDC::Sidekiq::ProcessorFailureError) do
      job_class.new.perform(%w[a b])
    end

    assert_equal 2, error.failures.length
    assert_predicate error.failures, :frozen?
    assert_match(/2 item/, error.message)
  end

  def test_failed_scalar_result_raises_for_sidekiq_retry
    job_class = Class.new do
      include CDC::Sidekiq::ProcessorJob
      cdc_runtime :direct
      cdc_processor FailingProcessor
    end

    error = assert_raises(CDC::Sidekiq::ProcessorFailureError) do
      job_class.new.perform("a")
    end

    assert_equal 1, error.failures.length
  end

  def test_failed_results_can_be_returned_without_raising
    job_class = Class.new do
      include CDC::Sidekiq::ProcessorJob
      cdc_runtime :direct
      cdc_processor FailingProcessor
      cdc_raise_on_failure false
    end

    results = job_class.new.perform(%w[a b])

    assert_equal 2, results.length
    assert results.all?(&:failure?)
  end

  def test_global_raise_on_failure_false_returns_failures
    CDC::Sidekiq.configure { |config| config.raise_on_failure = false }
    job_class = Class.new do
      include CDC::Sidekiq::ProcessorJob
      cdc_runtime :direct
      cdc_processor FailingProcessor
    end

    result = job_class.new.perform("a")

    assert_predicate result, :failure?
  end

  def test_successful_result_does_not_raise_when_failure_policy_enabled
    job_class = Class.new do
      include CDC::Sidekiq::ProcessorJob
      cdc_runtime :direct
      cdc_processor RecordingProcessor
      cdc_raise_on_failure true
    end

    result = job_class.new.perform("a")

    assert_equal "a", result.value
  end

  def test_job_runtime_overrides_global_runtime
    CDC::Sidekiq.configure { |config| config.default_runtime = :parallel }

    job_class = Class.new do
      include CDC::Sidekiq::ProcessorJob
      cdc_runtime :direct
      cdc_processor RecordingProcessor
    end

    result = job_class.new.perform("a")

    assert_equal "a", result.value
  end

  def test_processor_class_is_instantiated_per_runtime_build
    job_class = Class.new do
      include CDC::Sidekiq::ProcessorJob
      cdc_runtime :direct
      cdc_processor RecordingProcessor
    end

    result = job_class.new.perform("a")

    assert_equal "a", result.value
  end

  def test_class_level_readers_return_configured_values
    processor = RecordingProcessor.new
    job_class = Class.new do
      include CDC::Sidekiq::ProcessorJob
    end

    assert_nil job_class.cdc_processor
    assert_nil job_class.cdc_runtime
    assert_nil job_class.cdc_parallel_size
    assert_nil job_class.cdc_concurrency
    assert_nil job_class.cdc_timeout
    assert_nil job_class.cdc_preserve_order
    assert_nil job_class.cdc_batch_payloads
    assert_nil job_class.cdc_raise_on_failure

    job_class.cdc_processor processor
    job_class.cdc_runtime "direct"
    job_class.cdc_parallel_size "2"
    job_class.cdc_concurrency "3"
    job_class.cdc_timeout "4.5"
    job_class.cdc_preserve_order false
    job_class.cdc_batch_payloads true
    job_class.cdc_raise_on_failure true

    assert_same processor, job_class.cdc_processor
    assert_equal :direct, job_class.cdc_runtime
    assert_equal 2, job_class.cdc_parallel_size
    assert_equal 3, job_class.cdc_concurrency
    assert_equal 4.5, job_class.cdc_timeout
    refute job_class.cdc_preserve_order
    assert job_class.cdc_batch_payloads
    assert job_class.cdc_raise_on_failure
  end

  def test_timeout_can_be_set_to_nil_after_having_value
    job_class = Class.new do
      include CDC::Sidekiq::ProcessorJob
      cdc_timeout 1
    end

    assert_equal 1.0, job_class.cdc_timeout

    job_class.cdc_timeout nil

    assert_nil job_class.cdc_timeout
  end

  def test_job_timeout_nil_overrides_global_timeout
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
            def process_many(items) = items.map { |item| @processor.process(item) }.freeze
            def shutdown = (@shutdown = true)
          end
        end
      end
    RUBY
    CDC::Sidekiq.configure { |config| config.timeout = 9.0 }
    job_class = Class.new do
      include CDC::Sidekiq::ProcessorJob
      cdc_runtime :concurrent
      cdc_processor RecordingProcessor
      cdc_timeout nil
    end

    result = job_class.new.perform("a")

    assert_equal "a", result.value
    assert_nil CDC::Concurrent::ProcessorPool.last_options.fetch(:timeout)
  end

  private

  def install_fake_runtime(name, source)
    dir = File.join(Dir.pwd, "tmp", "fake_#{name}_runtime")
    FileUtils.mkdir_p(File.join(dir, "cdc"))
    File.write(File.join(dir, "cdc", "#{name}.rb"), source)
    $LOAD_PATH.unshift(dir) unless $LOAD_PATH.include?(dir)
  end
end
