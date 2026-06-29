# frozen_string_literal: true

module Dekiru
  module DataMigration
    # Base class for data migration with testable method separation
    class Migration
      # Default batch size used by ActiveRecord's `in_batches` when `of:` is not given
      DEFAULT_BATCH_SIZE = 1000

      attr_accessor :batch_size

      def self.run(options = {})
        migration = new
        title = migration.title

        options = options.dup
        migration.batch_size = options.delete(:batch_size)

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

        target_count = targets.count
        log "Target count: #{target_count}"
        confirm?

        if migrate_batch_overridden?
          migrate_in_batches(targets, target_count)
        else
          migrate_each_record(targets)
        end

        log "Migration completed"
      end

      def migration_targets
        raise NotImplementedError, "#{self.class}#migration_targets must be implemented"
      end

      def migrate_record(record)
        raise NotImplementedError, "#{self.class}#migrate_record must be implemented"
      end

      def migrate_batch(relation)
        raise NotImplementedError, "#{self.class}#migrate_batch must be implemented"
      end

      private

      def migrate_in_batches(targets, target_count)
        size = batch_size || DEFAULT_BATCH_SIZE
        batches = batch_size ? targets.in_batches(of: batch_size) : targets.in_batches
        total = (target_count.to_f / size).ceil
        each_with_progress(batches, total: total) do |batch|
          migrate_batch(batch)
        end
      end

      def migrate_each_record(targets)
        options = batch_size ? { batch_size: batch_size } : {}
        find_each_with_progress(targets, options) do |record|
          migrate_record(record)
        end
      end

      def migrate_batch_overridden?
        self.class.instance_method(:migrate_batch).owner != Dekiru::DataMigration::Migration
      end

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
