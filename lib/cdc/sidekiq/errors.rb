# frozen_string_literal: true

module CDC
  module Sidekiq
    # Base error for all cdc-sidekiq failures.
    class Error < StandardError; end

    # Raised when a job declares an unsupported CDC runtime.
    class UnsupportedRuntimeError < Error; end

    # Raised when a Sidekiq processor job does not declare a processor.
    class MissingProcessorError < Error; end

    # Raised when processor execution returns one or more failed results.
    class ProcessorFailureError < Error
      # @return [Array<Object>] failed processor results that triggered the error.
      attr_reader :failures

      # @param failures [Array<Object>] failed processor results that should be exposed to Sidekiq retry handling.
      # @return [void]
      def initialize(failures)
        @failures = failures.freeze
        super("CDC processor failed for #{failures.length} item(s)")
      end
    end
  end
end
