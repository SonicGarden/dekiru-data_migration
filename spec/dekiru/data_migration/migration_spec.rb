# frozen_string_literal: true

require "spec_helper"
require "ostruct"

# Dummy class for testing
class TestMigration < Dekiru::DataMigration::Migration
  attr_reader :targets, :migrated_records

  def initialize
    super
    @targets = (1..3).to_a.map { |i| OpenStruct.new(id: i) }
    @migrated_records = []
  end

  def migration_targets
    # Simulate a scope for testing
    scope = OpenStruct.new(count: @targets.size)

    # Override the find_each method
    scope.define_singleton_method(:find_each) do |&block|
      @targets.each(&block)
    end

    scope.instance_variable_set(:@targets, @targets)
    scope
  end

  def migrate_record(record)
    @migrated_records << record
  end
end

# Dummy class implementing migrate_batch
class BatchTestMigration < Dekiru::DataMigration::Migration
  attr_reader :targets, :migrated_batches, :received_of

  def initialize
    super
    @targets = (1..3).to_a.map { |i| OpenStruct.new(id: i) }
    @migrated_batches = []
  end

  def migration_targets
    scope = OpenStruct.new(count: @targets.size)

    # in_batches returns an enumerable that yields each batch as a Relation.
    # Record the requested batch size (of:) so tests can assert it is forwarded.
    targets = @targets
    record_of = ->(of) { @received_of = of }
    scope.define_singleton_method(:in_batches) do |of: nil, &block|
      record_of.call(of)
      slice = of || 2
      targets.each_slice(slice).each(&block)
    end

    scope
  end

  def migrate_batch(relation)
    @migrated_batches << relation
  end
end

RSpec.describe Dekiru::DataMigration::Migration do # rubocop:disable Metrics/BlockLength
  let(:migration) { TestMigration.new }

  describe ".run" do
    it "calls Operator.execute and runs migrate" do
      allow(Dekiru::DataMigration::Operator).to receive(:execute)
        .with("Test migration", {})
        .and_yield

      # Verify that migrate is called
      expect_any_instance_of(TestMigration).to receive(:migrate)

      TestMigration.run
    end

    it "passes options to Operator.execute" do
      options = { warning_side_effects: false }
      expect(Dekiru::DataMigration::Operator).to receive(:execute)
        .with("Test migration", options)

      TestMigration.run(options)
    end

    it "extracts batch_size from the options before passing them to Operator.execute" do
      # batch_size is consumed by Migration, so Operator.execute must not see it
      expect(Dekiru::DataMigration::Operator).to receive(:execute)
        .with("Test migration", { warning_side_effects: false })

      TestMigration.run(batch_size: 500, warning_side_effects: false)
    end

    it "assigns batch_size to the migration instance" do
      allow(Dekiru::DataMigration::Operator).to receive(:execute)
      assigned = nil
      allow_any_instance_of(TestMigration).to receive(:batch_size=) { |_, value| assigned = value }

      TestMigration.run(batch_size: 500)

      expect(assigned).to eq(500)
    end
  end

  describe "#title" do
    it "generates an appropriate title from the class name" do
      expect(migration.title).to eq("Test migration")
    end
  end

  describe "#migrate" do
    it "calls migration_targets and outputs logs" do
      allow(migration).to receive(:log)
      allow(migration).to receive(:find_each_with_progress).and_call_original

      migration.migrate

      expect(migration.migrated_records.size).to eq(3)
    end
  end

  describe "#migrate (batch path)" do
    let(:batch_migration) { BatchTestMigration.new }

    it "processes batches with each_with_progress when migrate_batch is implemented" do
      allow(batch_migration).to receive(:log)
      expect(batch_migration).to receive(:each_with_progress).and_call_original
      expect(batch_migration).not_to receive(:find_each_with_progress)

      batch_migration.migrate

      # 3 records split into batches of 2 => 2 batches
      expect(batch_migration.migrated_batches.size).to eq(2)
    end

    it "processes records with find_each_with_progress when migrate_batch is not implemented" do
      allow(migration).to receive(:log)
      expect(migration).to receive(:find_each_with_progress).and_call_original
      expect(migration).not_to receive(:each_with_progress)

      migration.migrate

      expect(migration.migrated_records.size).to eq(3)
    end
  end

  describe "#migrate (batch_size)" do
    let(:batch_migration) { BatchTestMigration.new }

    it "forwards batch_size to in_batches as of:" do
      allow(batch_migration).to receive(:log)
      batch_migration.batch_size = 1

      batch_migration.migrate

      expect(batch_migration.received_of).to eq(1)
      # 3 records split into batches of 1 => 3 batches
      expect(batch_migration.migrated_batches.size).to eq(3)
    end

    it "calls in_batches without of: when batch_size is not set" do
      allow(batch_migration).to receive(:log)

      batch_migration.migrate

      expect(batch_migration.received_of).to be_nil
    end
  end

  describe "#migration_targets" do
    it "raises NotImplementedError in the base class" do
      base_migration = described_class.new
      expect { base_migration.migration_targets }.to raise_error(NotImplementedError)
    end
  end

  describe "#migrate_record" do
    it "raises NotImplementedError in the base class" do
      base_migration = described_class.new
      record = OpenStruct.new(id: 1)
      expect { base_migration.migrate_record(record) }.to raise_error(NotImplementedError)
    end
  end

  describe "#migrate_batch" do
    it "raises NotImplementedError in the base class" do
      base_migration = described_class.new
      relation = OpenStruct.new
      expect { base_migration.migrate_batch(relation) }.to raise_error(NotImplementedError)
    end
  end

  describe "default behavior during tests" do
    describe "#log" do
      it "calls puts" do
        expect { migration.send(:log, "test message") }.to output("test message\n").to_stdout
      end
    end

    describe "#find_each_with_progress" do
      it "calls find_each without a progress bar" do
        scope = migration.migration_targets
        results = []

        migration.send(:find_each_with_progress, scope) do |record|
          results << record
        end

        expect(results.size).to eq(3)
      end
    end

    describe "#each_with_progress" do
      it "calls each without a progress bar" do
        enum = [1, 2, 3]
        results = []

        migration.send(:each_with_progress, enum) do |item|
          results << item
        end

        expect(results).to eq([1, 2, 3])
      end
    end
  end
end
