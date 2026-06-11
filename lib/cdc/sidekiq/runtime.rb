# frozen_string_literal: true

module CDC
  module Sidekiq
    # Executes a CDC processor through one of the CDC runtime primitives.
    #
    # Runtime is intentionally selected outside Sidekiq's own concurrency
    # setting. Sidekiq concurrency controls how many jobs run at once. This
    # object controls how one CDC-aware job fans work out internally.
    class Runtime
      # @param processor [Object] CDC processor object that responds to #process.
      # @param runtime [Symbol] execution runtime, currently :parallel, :concurrent, or :direct.
      # @param parallel_size [Integer] number of Ractors used by cdc-parallel.
      # @param concurrency [Integer] number of Async tasks used by cdc-concurrent.
      # @param timeout [Float, nil] optional timeout passed to the selected runtime.
      # @param preserve_order [Boolean] whether cdc-concurrent should preserve input order.
      # @return [void] returns nothing.
      def initialize(processor:, runtime:, parallel_size:, concurrency:, timeout:, preserve_order:)
        @processor = processor
        @runtime = runtime.to_sym
        @parallel_size = parallel_size
        @concurrency = concurrency
        @timeout = timeout
        @preserve_order = preserve_order
      end

      # Process one work item through the selected runtime.
      #
      # @param item [Object] work item passed to the processor.
      # @return [Object] processor result returned by the selected runtime.
      def process(item)
        with_pool { |pool| pool.process(item) }
      end

      # Process many work items through the selected runtime.
      #
      # @param items [Array<Object>] work items passed to the processor.
      # @return [Array<Object>] processor results returned by the selected runtime.
      def process_many(items)
        with_pool { |pool| pool.process_many(items) }
      end

      private

      attr_reader :processor, :runtime, :parallel_size, :concurrency, :timeout, :preserve_order

      def with_pool
        pool = build_pool
        yield pool
      ensure
        pool.shutdown if pool.respond_to?(:shutdown)
      end

      def build_pool
        case runtime
        when :parallel
          require "cdc/parallel"
          CDC::Parallel::ProcessorPool.new(processor:, size: parallel_size, timeout:)
        when :concurrent
          require "cdc/concurrent"
          CDC::Concurrent::ProcessorPool.new(processor:, concurrency:, timeout:, preserve_order:)
        when :direct
          DirectPool.new(processor)
        else
          raise UnsupportedRuntimeError, "unsupported CDC Sidekiq runtime: #{runtime.inspect}"
        end
      end

      # Minimal runtime used for tests and simple sequential execution.
      class DirectPool
        # @param processor [Object] CDC processor object that responds to #process.
        # @return [void] returns nothing.
        def initialize(processor)
          @processor = processor
        end

        # @param item [Object] work item passed to the processor.
        # @return [Object] processor result returned by the processor.
        def process(item)
          @processor.process(item)
        end

        # @param items [Array<Object>] work items passed to the processor.
        # @return [Array<Object>] processor results returned by the processor.
        def process_many(items)
          items.map { |item| process(item) }.freeze
        end
      end
    end
  end
end
