# frozen_string_literal: true

require "active_support/all"
require "ruby-progressbar"
require_relative "data_migration/dangerous_method_refinement"

module Dekiru
  module DataMigration
    # Data migration operator with transaction control and progress tracking
    class Operator # rubocop:disable Metrics/ClassLength
      class NestedTransactionError < StandardError; end

      attr_reader :title, :stream, :logger, :result, :canceled, :started_at, :ended_at, :error

      def self.execute(title, options = {}, &block)
        new(title, options).execute(&block)
      end

      def initialize(title, options = {})
        @title = title
        @options = options
        @logger = @options.fetch(:logger) do
          Logger.new(Rails.root.join("log/data_migration_#{Time.current.strftime("%Y%m%d%H%M")}.log"))
        end
        @stream = @options.fetch(:output, $stdout)
        @without_transaction = @options.fetch(:without_transaction, false)
        @side_effects = Hash.new do |hash, key|
          hash[key] = Hash.new(0)
        end
      end

      def execute(&block) # rubocop:disable Metrics/AbcSize,Metrics/MethodLength
        @started_at = Time.current
        log "Start: #{title} at #{started_at}\n\n"
        if @without_transaction
          run(&block)
          @result = true
        else
          raise NestedTransactionError if current_transaction_open?

          @result = transaction_provider.within_transaction do
            run(&block)
            log "Finished execution: #{title}"
            confirm?("\nAre you sure to commit?")
          end
        end
        log "Finished successfully: #{title}" if @result == true
      rescue StandardError => e
        @error = e
        @result = false
      ensure
        @ended_at = Time.current
        log "Total time: #{duration.round(2)} sec"

        raise error if error

        return @result # rubocop:disable Lint/EnsureReturn
      end

      def duration
        ((ended_at || Time.current) - started_at)
      end

      def each_with_progress(enum, options = {}) # rubocop:disable Metrics/MethodLength
        options = options.dup
        options[:total] ||= begin
          (enum.size == Float::INFINITY ? nil : enum.size)
        rescue StandardError
          nil
        end
        options[:format] ||= options[:total] ? "%a |%b>>%i| %p%% %t" : "%a |%b>>%i| ??%% %t"
        options[:output] = stream

        @pb = ::ProgressBar.create(options)
        enum.each do |item|
          yield item
          @pb.increment
        end
        @pb.finish
      end

      def find_each_with_progress(target_scope, options = {}, &block)
        # `LocalJumpError: no block given (yield)` が出る場合、 find_each メソッドが enumerator を返していない可能性があります
        # 直接 each_with_progress を使うか、 find_each が enumerator を返すように修正してください
        each_with_progress(target_scope.find_each, options, &block)
      end

      private

      def log(message)
        if @pb && !@pb.finished?
          @pb.log(message)
        else
          stream.puts(message)
        end

        logger&.info(message.squish)
      end

      def confirm?(message = "Are you sure?") # rubocop:disable Metrics/MethodLength
        loop do
          stream.print "#{message} (yes/no) > "
          case $stdin.gets.strip
          when "yes"
            newline
            return true
          when "no"
            newline
            cancel!
          end
        end
      end

      def newline
        stream.puts("")
      end

      def cancel!
        log "Canceled: #{title}"
        raise ActiveRecord::Rollback
      end

      def handle_notification(*args) # rubocop:disable Metrics/AbcSize
        event = ActiveSupport::Notifications::Event.new(*args)

        increment_side_effects(:enqueued_jobs, event.payload[:job].class.name) if event.payload[:job]
        increment_side_effects(:delivered_mailers, event.payload[:mailer]) if event.payload[:mailer]

        return unless event.payload[:sql] && /\A\s*(insert|update|delete)/i.match?(event.payload[:sql])

        increment_side_effects(:write_queries, event.payload[:sql])
      end

      def increment_side_effects(type, value)
        @side_effects[type][value] += 1
      end

      def warning_side_effects(&block)
        ActiveSupport::Notifications.subscribed(method(:handle_notification), /^(sql|enqueue|deliver)/) do
          instance_eval(&block)
        end

        @side_effects.each do |name, items|
          newline
          log "#{name.to_s.titlecase}!!"
          items.sort_by { |_v, c| c }.reverse.slice(0, 20).each do |value, count|
            log "#{count} call: #{value}"
          end
        end
      end

      def run(&block)
        if @options.fetch(:warning_side_effects, true)
          warning_side_effects(&block)
        else
          instance_eval(&block)
        end
      end

      def transaction_provider
        Dekiru::DataMigration.configuration.transaction_provider
      end

      def current_transaction_open?
        transaction_provider.current_transaction_open?
      end
    end
  end
end
