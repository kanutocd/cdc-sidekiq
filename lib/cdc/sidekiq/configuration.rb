# frozen_string_literal: true

require "etc"

module CDC
  module Sidekiq
    # Runtime defaults shared by CDC-aware Sidekiq jobs.
    #
    # The configuration intentionally describes only the CDC execution layer.
    # Sidekiq still owns queue selection, scheduling, retries, durability, and
    # job concurrency. cdc-sidekiq owns runtime selection for work performed
    # inside a Sidekiq job.
    class Configuration
      # @return [Symbol] default runtime used when a job does not declare one.
      attr_accessor :default_runtime

      # @return [Integer] default number of Ractor workers for cdc-parallel jobs.
      attr_accessor :parallel_size

      # @return [Integer] default number of Async tasks for cdc-concurrent jobs.
      attr_accessor :concurrency

      # @return [Float, nil] default per-item timeout passed to CDC processor pools.
      attr_accessor :timeout

      # @return [Boolean] default result-ordering policy for cdc-concurrent jobs.
      attr_accessor :preserve_order

      # @return [Boolean] default failure policy for processor jobs.
      attr_accessor :raise_on_failure

      # @return [Boolean] whether array payloads should be processed with #process_many by default.
      attr_accessor :batch_payloads

      # @return [void]
      def initialize
        @default_runtime = :concurrent
        @parallel_size = [Etc.nprocessors - 1, 1].max
        @concurrency = 100
        @timeout = nil
        @preserve_order = true
        @raise_on_failure = true
        @batch_payloads = true
      end

      # Build an immutable copy so job-level overrides cannot mutate globals.
      #
      # @return [Configuration] independent copy of this configuration.
      def dup
        copy = self.class.new
        copy.default_runtime = default_runtime
        copy.parallel_size = parallel_size
        copy.concurrency = concurrency
        copy.timeout = timeout
        copy.preserve_order = preserve_order
        copy.raise_on_failure = raise_on_failure
        copy.batch_payloads = batch_payloads
        copy
      end
    end
  end
end
