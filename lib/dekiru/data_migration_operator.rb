# frozen_string_literal: true

require_relative "data_migration/operator"
require "active_support/deprecation"

module Dekiru
  # Alias for backward compatibility
  # Please use Dekiru::DataMigration::Operator in new code
  class DataMigrationOperator < DataMigration::Operator
    def self.new(...)
      ActiveSupport::Deprecation.new.warn(
        "Dekiru::DataMigrationOperator is deprecated. " \
        "Use Dekiru::DataMigration::Operator instead."
      )
      DataMigration::Operator.new(...)
    end
  end
end
