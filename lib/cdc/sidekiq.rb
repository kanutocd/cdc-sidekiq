# frozen_string_literal: true

require_relative "sidekiq/version"
require_relative "sidekiq/errors"
require_relative "sidekiq/configuration"
require_relative "sidekiq/runtime"
require_relative "sidekiq/processor_job"

module CDC
  # Integration layer between Sidekiq and CDC execution primitives.
  module Sidekiq
    class << self
      # Read the process-wide cdc-sidekiq configuration.
      #
      # @return [Configuration] mutable global configuration object.
      def configuration
        @configuration ||= Configuration.new
      end

      # Configure process-wide defaults for CDC-aware Sidekiq jobs.
      #
      # @yieldparam configuration [Configuration] mutable configuration object.
      # @return [Configuration] configured global configuration object.
      def configure
        yield configuration if block_given?
        configuration
      end

      # Reset process-wide configuration to defaults.
      #
      # @return [Configuration] new default configuration object.
      def reset_configuration!
        @configuration = Configuration.new
      end
    end
  end
end
