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
    it "confirm で yes" do
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

    it "confirm で no" do
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

    it "処理中に例外" do
      expect do
        operator.execute { raise ArgumentError }
      end.to raise_error(ArgumentError)

      expect(operator.result).to eq(false)
      expect(operator.error.class).to eq(ArgumentError)
      expect(operator.stream.out).not_to include("Are you sure to commit?")
      expect(operator.stream.out).not_to include("Canceled:")
      expect(operator.stream.out).to include("Total time:")
    end

    context "トランザクション内で呼び出された場合" do
      before { allow(operator).to receive(:current_transaction_open?) { true } }

      it "例外が発生すること" do
        expect do
          operator.execute do
            log "processing"
            sleep 1.0
          end
        end.to raise_error(Dekiru::DataMigration::Operator::NestedTransactionError)
      end
    end

    context "without_transaction: true のとき" do
      let(:without_transaction) { true }

      it "トランザクションがかからないこと" do
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
    it "進捗が表示される" do
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

    it "total をオプションで渡すことができる" do
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
  end

  describe "#find_each_with_progress" do
    it "進捗が表示される" do
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

    it "total をオプションで渡すことができる" do
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
  end
end
# rubocop:enable Metrics/BlockLength
