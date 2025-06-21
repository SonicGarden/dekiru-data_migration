# frozen_string_literal: true

require "active_record"

module Dekiru
  module DataMigration
    # Provides transaction management functionality for data migrations.
    # Wraps ActiveRecord transaction operations to ensure data consistency
    # during migration operations.
    class TransactionProvider
      # Executes the given block within a database transaction.
      # @yield Block to execute within transaction
      def within_transaction(&)
        ActiveRecord::Base.transaction(&)
      end

      # Checks if there is currently an open database transaction.
      # @return [Boolean] true if transaction is open, false otherwise
      def current_transaction_open?
        ActiveRecord::Base.connection.current_transaction.open?
      end
    end
  end
end
