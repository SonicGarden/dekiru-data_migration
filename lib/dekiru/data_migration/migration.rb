# frozen_string_literal: true

module Dekiru
  module DataMigration
    # Base class for data migration with testable method separation
    class Migration
      def self.run(options = {})
        migration = new
        title = migration.title

        Operator.execute(title, options) do
          migration.instance_variable_set(:@operator_context, self)
          migration.migrate
        end
      end

      def title
        self.class.name.demodulize.underscore.humanize
      end

      def migrate
        targets = migration_targets

        log "Target count: #{targets.count}"
        confirm?

        find_each_with_progress(targets) do |record|
          migrate_record(record)
        end

        log "Migration completed"
      end

      def migration_targets
        raise NotImplementedError, "#{self.class}#migration_targets must be implemented"
      end

      def migrate_record(record)
        raise NotImplementedError, "#{self.class}#migrate_record must be implemented"
      end

      private

      def confirm?
        if @operator_context
          @operator_context.send(:confirm?)
        else
          # Default behavior during test (no confirmation)
          puts "Confirmation skipped in test mode"
        end
      end

      def log(message)
        if @operator_context
          @operator_context.send(:log, message)
        else
          # Default behavior during test
          puts message
        end
      end

      def find_each_with_progress(scope, options = {}, &block)
        if @operator_context
          @operator_context.send(:find_each_with_progress, scope, options, &block)
        else
          # Default behavior during test (no progress bar)
          scope.find_each(&block)
        end
      end

      def each_with_progress(enum, options = {}, &block)
        if @operator_context
          @operator_context.send(:each_with_progress, enum, options, &block)
        else
          # Default behavior during test (no progress bar)
          enum.each(&block)
        end
      end
    end
  end
end
