# frozen_string_literal: true

require "test_helper"

class ConfigurationTest < Minitest::Test
  def setup
    CDC::Sidekiq.reset_configuration!
  end

  def test_defaults_are_safe_for_sidekiq_processes
    configuration = CDC::Sidekiq.configuration

    assert_equal :concurrent, configuration.default_runtime
    assert_operator configuration.parallel_size, :>=, 1
    assert_equal 100, configuration.concurrency
    assert_nil configuration.timeout
    assert configuration.preserve_order
    assert configuration.raise_on_failure
    assert configuration.batch_payloads
  end

  def test_configure_yields_global_configuration
    CDC::Sidekiq.configure do |config|
      config.default_runtime = :parallel
      config.parallel_size = 2
      config.concurrency = 10
      config.timeout = 0.5
      config.preserve_order = false
      config.raise_on_failure = false
      config.batch_payloads = false
    end

    configuration = CDC::Sidekiq.configuration
    assert_equal :parallel, configuration.default_runtime
    assert_equal 2, configuration.parallel_size
    assert_equal 10, configuration.concurrency
    assert_equal 0.5, configuration.timeout
    refute configuration.preserve_order
    refute configuration.raise_on_failure
    refute configuration.batch_payloads
  end

  def test_configure_without_block_returns_configuration
    configuration = CDC::Sidekiq.configure

    assert_same CDC::Sidekiq.configuration, configuration
  end

  def test_reset_configuration_returns_new_default_configuration
    old_configuration = CDC::Sidekiq.configuration
    old_configuration.default_runtime = :direct

    new_configuration = CDC::Sidekiq.reset_configuration!

    refute_same old_configuration, new_configuration
    assert_equal :concurrent, new_configuration.default_runtime
  end

  def test_dup_copies_values_without_sharing_configuration_object
    configuration = CDC::Sidekiq.configuration
    configuration.default_runtime = :parallel
    configuration.parallel_size = 8
    configuration.concurrency = 55
    configuration.timeout = 2.25
    configuration.preserve_order = false
    configuration.raise_on_failure = false
    configuration.batch_payloads = false

    copy = configuration.dup
    copy.default_runtime = :direct
    copy.parallel_size = 1

    assert_equal :parallel, configuration.default_runtime
    assert_equal 8, configuration.parallel_size
    assert_equal :direct, copy.default_runtime
    assert_equal 1, copy.parallel_size
    assert_equal 55, copy.concurrency
    assert_equal 2.25, copy.timeout
    refute copy.preserve_order
    refute copy.raise_on_failure
    refute copy.batch_payloads
  end
end
