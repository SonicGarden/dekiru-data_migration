# frozen_string_literal: true

require_relative "data_migration/version"
require_relative "data_migration/transaction_provider"
require_relative "data_migration_operator"

module Dekiru
  module DataMigration
    class << self
      def configure
        yield(configuration)
      end

      def configuration
        @configuration ||= Configuration.new
      end
    end

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
