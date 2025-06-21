# frozen_string_literal: true

require_relative "data_migration/version"
require_relative "data_migration/transaction_provider"
require_relative "data_migration_operator"

module Dekiru
  # The DataMigration module provides configuration and error handling
  # for data migration tasks. It allows users to set up custom
  # configuration options such as the maintenance script directory and
  # transaction provider. The module exposes a `configure` method for
  # block-based configuration and defines a custom error class for
  # migration-related exceptions.
  module DataMigration
    class << self
      def configure
        yield(configuration)
      end

      def configuration
        @configuration ||= Configuration.new
      end
    end

    # Configuration class for Dekiru Data Migration.
    class Configuration
      attr_accessor :maintenance_script_directory, :transaction_provider

      def initialize
        @maintenance_script_directory = "scripts"
        @transaction_provider = TransactionProvider.new
      end
    end

    class Error < StandardError; end
    # Your code goes here...
  end
end
