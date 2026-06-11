# frozen_string_literal: true

module CDC
  module Sidekiq
    # Sidekiq job mixin that executes work through CDC runtime primitives.
    #
    # The job remains a normal Sidekiq job. Sidekiq still owns scheduling,
    # retries, queues, and persistence. cdc-sidekiq only changes how the job
    # executes its payload once Sidekiq has started the job.
    #
    # @example Process many items through cdc-parallel
    #   class ReindexUsersJob
    #     include Sidekiq::Job
    #     include CDC::Sidekiq::ProcessorJob
    #
    #     cdc_processor UserIndexer
    #     cdc_runtime :parallel
    #   end
    #
    # @example Process I/O-heavy items through cdc-concurrent
    #   class DeliverWebhooksJob
    #     include Sidekiq::Job
    #     include CDC::Sidekiq::ProcessorJob
    #
    #     cdc_processor WebhookDeliverer
    #     cdc_runtime :concurrent
    #     cdc_concurrency 250
    #   end
    module ProcessorJob
      # Add CDC processor-job class methods to the including job class.
      #
      # @param base [Class] Sidekiq job class including this module.
      # @return [void] returns nothing.
      def self.included(base)
        base.extend(ClassMethods)
      end

      # Execute a Sidekiq payload through the configured CDC runtime.
      #
      # Array payloads are processed with #process_many when cdc_batch_payloads
      # is enabled. Other payloads are processed with #process.
      #
      # @param payload [Object, Array<Object>] Sidekiq job payload or batch payload.
      # @return [Object, Array<Object>] CDC processor result or frozen result array.
      # @raise [MissingProcessorError] when the job does not declare a CDC processor.
      # @raise [ProcessorFailureError] when raise-on-failure is enabled and one or more results failed.
      def perform(payload)
        results = process_payload(payload)
        handle_processor_failures(results)
        results
      end

      private

      def process_payload(payload)
        job_class = self.class
        # @type var job_class: untyped
        runtime = job_class.__cdc_sidekiq_runtime
        if payload.is_a?(Array) && job_class.__cdc_sidekiq_batch_payloads
          runtime.process_many(payload)
        else
          runtime.process(payload)
        end
      end

      def handle_processor_failures(results)
        job_class = self.class
        # @type var job_class: untyped
        return unless job_class.__cdc_sidekiq_raise_on_failure

        failures = Array(results).select do |result|
          # @type var result: untyped
          result.respond_to?(:failure?) && result.failure?
        end
        raise ProcessorFailureError, failures unless failures.empty?
      end

      # Class-level declaration helpers for CDC-aware Sidekiq jobs.
      module ClassMethods
        # Declare or read the processor used by this job.
        #
        # @param value [Class, Object, nil] processor class or processor instance.
        # @return [Class, Object, nil] configured processor when called without an argument.
        def cdc_processor(value = nil)
          return @cdc_processor if value.nil?

          @cdc_processor = value
        end

        # Declare or read the CDC runtime used by this job.
        #
        # @param value [Symbol, String, nil] runtime name, such as :parallel, :concurrent, or :direct.
        # @return [Symbol, nil] configured runtime when called without an argument.
        def cdc_runtime(value = nil)
          return @cdc_runtime if value.nil?

          @cdc_runtime = value.to_sym
        end

        # Declare or read the cdc-parallel worker count for this job.
        #
        # @param value [Integer, nil] number of Ractor workers for this job.
        # @return [Integer, nil] configured worker count when called without an argument.
        def cdc_parallel_size(value = nil)
          return @cdc_parallel_size if value.nil?

          @cdc_parallel_size = Integer(value)
        end

        # Declare or read the cdc-concurrent task concurrency for this job.
        #
        # @param value [Integer, nil] maximum Async task count for this job.
        # @return [Integer, nil] configured concurrency when called without an argument.
        def cdc_concurrency(value = nil)
          return @cdc_concurrency if value.nil?

          @cdc_concurrency = Integer(value)
        end

        # Declare or read the runtime timeout for this job.
        #
        # @param value [Float, Integer, nil] timeout in seconds, or nil for no timeout.
        # @return [Float, nil] configured timeout when called without an argument.
        def cdc_timeout(value = :__cdc_sidekiq_read__)
          return @cdc_timeout if value == :__cdc_sidekiq_read__

          @cdc_timeout = value.nil? ? nil : Float(value)
        end

        # Declare or read result ordering for cdc-concurrent.
        #
        # @param value [Boolean, nil] true to preserve input order, false to keep completion order.
        # @return [Boolean, nil] configured ordering policy when called without an argument.
        def cdc_preserve_order(value = nil)
          return @cdc_preserve_order if value.nil?

          @cdc_preserve_order = value == true
        end

        # Declare or read whether array payloads use #process_many.
        #
        # @param value [Boolean, nil] true to batch array payloads, false to process the array as one item.
        # @return [Boolean, nil] configured batching policy when called without an argument.
        def cdc_batch_payloads(value = nil)
          return @cdc_batch_payloads if value.nil?

          @cdc_batch_payloads = value == true
        end

        # Declare or read whether failed ProcessorResult objects raise.
        #
        # @param value [Boolean, nil] true to raise on failed results so Sidekiq retries the job.
        # @return [Boolean, nil] configured failure policy when called without an argument.
        def cdc_raise_on_failure(value = nil)
          return @cdc_raise_on_failure if value.nil?

          @cdc_raise_on_failure = value == true
        end

        # Build the runtime used by one Sidekiq job invocation.
        #
        # @return [Runtime] runtime configured for this job class.
        # @raise [MissingProcessorError] when no processor has been declared.
        def __cdc_sidekiq_runtime
          Runtime.new(
            processor: __cdc_sidekiq_processor,
            runtime: __cdc_sidekiq_runtime_name,
            parallel_size: __cdc_sidekiq_parallel_size,
            concurrency: __cdc_sidekiq_concurrency,
            timeout: __cdc_sidekiq_timeout,
            preserve_order: __cdc_sidekiq_preserve_order
          )
        end

        # @return [Boolean] true when array payloads should use #process_many.
        def __cdc_sidekiq_batch_payloads
          configured_boolean(@cdc_batch_payloads, CDC::Sidekiq.configuration.batch_payloads)
        end

        # @return [Boolean] true when failed results should raise.
        def __cdc_sidekiq_raise_on_failure
          configured_boolean(@cdc_raise_on_failure, CDC::Sidekiq.configuration.raise_on_failure)
        end

        private

        def __cdc_sidekiq_processor
          processor = @cdc_processor
          raise MissingProcessorError, "#{__send__(:name)} must declare cdc_processor" unless processor

          processor.is_a?(Class) ? processor.new : processor
        end

        def __cdc_sidekiq_runtime_name
          @cdc_runtime || CDC::Sidekiq.configuration.default_runtime
        end

        def __cdc_sidekiq_parallel_size
          @cdc_parallel_size || CDC::Sidekiq.configuration.parallel_size
        end

        def __cdc_sidekiq_concurrency
          @cdc_concurrency || CDC::Sidekiq.configuration.concurrency
        end

        def __cdc_sidekiq_timeout
          defined?(@cdc_timeout) ? @cdc_timeout : CDC::Sidekiq.configuration.timeout
        end

        def __cdc_sidekiq_preserve_order
          configured_boolean(@cdc_preserve_order, CDC::Sidekiq.configuration.preserve_order)
        end

        def configured_boolean(value, fallback)
          value.nil? ? fallback : value
        end
      end
    end
  end
end
