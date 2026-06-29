# frozen_string_literal: true

# rubocop:disable Metrics/BlockLength
require "spec_helper"

class Dekiru::DummyStream # rubocop:disable Style/ClassAndModuleChildren
  attr_reader :out

  def initialize
    @out = ""
  end

  def puts(text)
    @out = out + "#{text}\n"
  end

  def print(text)
    @out = out + text
  end

  def tty?
    false
  end

  def flush
    # dummy
  end
end

class Dekiru::DummyRecord # rubocop:disable Style/ClassAndModuleChildren
  def self.count
    raise "won't call"
  end

  def self.each
    yield 99
  end

  def self.find_each
    if block_given?
      yield 99
    else
      Enumerator.new { |y| y << 99 }
    end
  end
end

class ActiveRecord::Base # rubocop:disable Style/ClassAndModuleChildren
  def self.transaction(*args)
    yield(*args)
  end
end

# Mimics ActiveRecord::Batches::BatchEnumerator, which is Enumerable but does NOT respond to #size.
class Dekiru::DummyBatchEnumerator # rubocop:disable Style/ClassAndModuleChildren
  include Enumerable

  def initialize(batches)
    @batches = batches
  end

  def each(&block)
    @batches.each(&block)
  end
  # Intentionally does not define #size, to reproduce the NoMethodError from BatchEnumerator.
end

RSpec.describe Dekiru::DataMigration::Operator do
  let(:dummy_stream) do
    Dekiru::DummyStream.new
  end
  let(:without_transaction) { false }
  let(:operator) do
    op = Dekiru::DataMigration::Operator.new("dummy", output: dummy_stream, logger: nil,
                                                      without_transaction: without_transaction)
    allow(op).to receive(:current_transaction_open?) { false }
    op
  end

  describe "#execute" do
    it "commits when confirm is yes" do
      allow($stdin).to receive(:gets) do
        "yes\n"
      end

      expect do
        operator.execute do
          log "processing"
          sleep 1.0
        end
      end.not_to raise_error

      expect(operator.result).to eq(true)
      expect(operator.duration).to be_within(0.1).of(1.0)
      expect(operator.error).to eq(nil)
      expect(operator.stream.out).to include("Are you sure to commit?")
      expect(operator.stream.out).to include("Finished successfully:")
      expect(operator.stream.out).to include("Total time:")
    end

    it "rolls back when confirm is no" do
      allow($stdin).to receive(:gets) do
        "no\n"
      end

      expect do
        operator.execute do
          log "processing"
          sleep 1.0
        end
      end.to raise_error(ActiveRecord::Rollback)

      expect(operator.result).to eq(false)
      expect(operator.duration).to be_within(0.1).of(1.0)
      expect(operator.error.class).to eq(ActiveRecord::Rollback)
      expect(operator.stream.out).to include("Are you sure to commit?")
      expect(operator.stream.out).to include("Canceled:")
      expect(operator.stream.out).to include("Total time:")
    end

    it "raises when an exception occurs during processing" do
      expect do
        operator.execute { raise ArgumentError }
      end.to raise_error(ArgumentError)

      expect(operator.result).to eq(false)
      expect(operator.error.class).to eq(ArgumentError)
      expect(operator.stream.out).not_to include("Are you sure to commit?")
      expect(operator.stream.out).not_to include("Canceled:")
      expect(operator.stream.out).to include("Total time:")
    end

    context "when called inside a transaction" do
      before { allow(operator).to receive(:current_transaction_open?) { true } }

      it "raises an error" do
        expect do
          operator.execute do
            log "processing"
            sleep 1.0
          end
        end.to raise_error(Dekiru::DataMigration::Operator::NestedTransactionError)
      end
    end

    context "with without_transaction: true" do
      let(:without_transaction) { true }

      it "does not wrap the work in a transaction" do
        expect do
          operator.execute do
            log "processing"
            sleep 1.0
          end
        end.not_to raise_error

        expect(operator.result).to eq(true)
        expect(operator.duration).to be_within(0.1).of(1.0)
        expect(operator.error).to eq(nil)
        expect(operator.stream.out).not_to include("Are you sure to commit?")
        expect(operator.stream.out).to include("Finished successfully:")
        expect(operator.stream.out).to include("Total time:")
      end
    end
  end

  describe "#each_with_progress" do
    it "displays progress" do
      record = (0...10)

      allow($stdin).to receive(:gets) do
        "yes\n"
      end

      sum = 0
      operator.execute do
        each_with_progress(record, title: "count up number") do |num|
          sum += num
        end
      end

      expect(sum).to eq(45)
      expect(operator.result).to eq(true)
      expect(operator.error).to eq(nil)
      expect(operator.stream.out).to include("Are you sure to commit?")
      expect(operator.stream.out).to include("count up number:")
      expect(operator.stream.out).to include("Finished successfully:")
      expect(operator.stream.out).to include("Total time:")
    end

    it "accepts total as an option" do
      allow($stdin).to receive(:gets) do
        "yes\n"
      end

      sum = 0
      operator.execute do
        each_with_progress(Dekiru::DummyRecord, title: "pass total as option", total: 1) do |num|
          sum += num
        end
      end

      expect(sum).to eq(99)
      expect(operator.result).to eq(true)
      expect(operator.error).to eq(nil)
      expect(operator.stream.out).to include("Are you sure to commit?")
      expect(operator.stream.out).to include("pass total as option:")
      expect(operator.stream.out).to include("Finished successfully:")
      expect(operator.stream.out).to include("Total time:")
    end

    it "uses the given total (percent format) even when the enum has no size" do
      allow($stdin).to receive(:gets) { "yes\n" }
      enum = Dekiru::DummyBatchEnumerator.new([[1, 2], [3]])

      # Passing total: bypasses the enum.size lookup, so a size-less enum like
      # ActiveRecord's BatchEnumerator gets a real percentage format ("%p%%"), not "??%".
      expect(ProgressBar).to receive(:create)
        .with(hash_including(total: 2, format: "%a |%b>>%i| %p%% %t"))
        .and_call_original

      operator.execute do
        each_with_progress(enum, title: "batches", total: 2) { |_batch| }
      end
    end

    it "falls back to the ??% format when size is unavailable and no total is given" do
      allow($stdin).to receive(:gets) { "yes\n" }
      enum = Dekiru::DummyBatchEnumerator.new([[1, 2], [3]])

      # enum.size raises NoMethodError -> total stays nil -> "??%" format.
      # This characterizes why migrate_in_batches must pass total: explicitly.
      expect(ProgressBar).to receive(:create)
        .with(hash_including(total: nil, format: "%a |%b>>%i| ??%% %t"))
        .and_call_original

      operator.execute do
        each_with_progress(enum, title: "batches") { |_batch| }
      end
    end
  end

  describe "#find_each_with_progress" do
    it "displays progress" do
      record = (0...10).to_a.tap do |r|
        r.singleton_class.alias_method(:find_each, :each)
      end

      allow($stdin).to receive(:gets) do
        "yes\n"
      end

      sum = 0
      operator.execute do
        find_each_with_progress(record, title: "count up number") do |num|
          sum += num
        end
      end

      expect(sum).to eq(45)
      expect(operator.result).to eq(true)
      expect(operator.error).to eq(nil)
      expect(operator.stream.out).to include("Are you sure to commit?")
      expect(operator.stream.out).to include("count up number:")
      expect(operator.stream.out).to include("Finished successfully:")
      expect(operator.stream.out).to include("Total time:")
    end

    it "accepts total as an option" do
      allow($stdin).to receive(:gets) do
        "yes\n"
      end

      sum = 0
      operator.execute do
        find_each_with_progress(Dekiru::DummyRecord, title: "pass total as option", total: 1) do |num|
          sum += num
        end
      end

      expect(sum).to eq(99)
      expect(operator.result).to eq(true)
      expect(operator.error).to eq(nil)
      expect(operator.stream.out).to include("Are you sure to commit?")
      expect(operator.stream.out).to include("pass total as option:")
      expect(operator.stream.out).to include("Finished successfully:")
      expect(operator.stream.out).to include("Total time:")
    end

    it "forwards batch_size to find_each" do
      allow($stdin).to receive(:gets) { "yes\n" }

      # batch_size is forwarded to find_each(batch_size:), not to the progress bar
      enumerator = Enumerator.new { |y| y << 99 }
      expect(Dekiru::DummyRecord).to receive(:find_each).with(batch_size: 5).and_return(enumerator)

      operator.execute do
        find_each_with_progress(Dekiru::DummyRecord, batch_size: 5) { |_num| }
      end

      expect(operator.result).to eq(true)
      expect(operator.error).to eq(nil)
    end

    it "calls find_each without arguments when batch_size is not given" do
      allow($stdin).to receive(:gets) { "yes\n" }

      enumerator = Enumerator.new { |y| y << 99 }
      expect(Dekiru::DummyRecord).to receive(:find_each).with(no_args).and_return(enumerator)

      operator.execute do
        find_each_with_progress(Dekiru::DummyRecord) { |_num| }
      end

      expect(operator.result).to eq(true)
      expect(operator.error).to eq(nil)
    end
  end
end
# rubocop:enable Metrics/BlockLength
