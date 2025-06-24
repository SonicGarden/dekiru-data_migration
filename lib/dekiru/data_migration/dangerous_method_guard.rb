# frozen_string_literal: true

module Dekiru
  module DataMigration
    # Refinement module to prevent dangerous methods from being executed
    module DangerousMethodGuard
      class Error < StandardError; end

      refine ::String do
        def delete(...)
          raise Error,
                "Dangerous method `String#delete` is not allowed in data migration tasks. Use `String#remove` instead."
        end
      end
    end
  end
end
