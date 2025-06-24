# frozen_string_literal: true

require "spec_helper"
require "ostruct"

# テスト用のダミークラス
class TestMigration < Dekiru::DataMigration::Migration
  attr_reader :targets, :migrated_records

  def initialize
    super
    @targets = (1..3).to_a.map { |i| OpenStruct.new(id: i) }
    @migrated_records = []
  end

  def migration_targets
    # テスト用のスコープをシミュレート
    scope = OpenStruct.new(count: @targets.size)

    # find_eachメソッドをオーバーライド
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

RSpec.describe Dekiru::DataMigration::Migration do # rubocop:disable Metrics/BlockLength
  let(:migration) { TestMigration.new }

  describe ".run" do
    it "Operator.executeを呼び出してmigrateを実行する" do
      allow(Dekiru::DataMigration::Operator).to receive(:execute)
        .with("Test migration", {})
        .and_yield

      # migrateメソッドの呼び出しを確認
      expect_any_instance_of(TestMigration).to receive(:migrate)

      TestMigration.run
    end

    it "オプションをOperator.executeに渡す" do
      options = { warning_side_effects: false }
      expect(Dekiru::DataMigration::Operator).to receive(:execute)
        .with("Test migration", options)

      TestMigration.run(options)
    end
  end

  describe "#title" do
    it "クラス名から適切なタイトルを生成する" do
      expect(migration.title).to eq("Test migration")
    end
  end

  describe "#migrate" do
    it "migration_targetsを呼び出してログを出力する" do
      allow(migration).to receive(:log)
      allow(migration).to receive(:find_each_with_progress).and_call_original

      migration.migrate

      expect(migration.migrated_records.size).to eq(3)
    end
  end

  describe "#migration_targets" do
    it "基底クラスでは NotImplementedError を投げる" do
      base_migration = described_class.new
      expect { base_migration.migration_targets }.to raise_error(NotImplementedError)
    end
  end

  describe "#migrate_record" do
    it "基底クラスでは NotImplementedError を投げる" do
      base_migration = described_class.new
      record = OpenStruct.new(id: 1)
      expect { base_migration.migrate_record(record) }.to raise_error(NotImplementedError)
    end
  end

  describe "テスト時のデフォルト動作" do
    describe "#log" do
      it "putsを呼び出す" do
        expect { migration.send(:log, "test message") }.to output("test message\n").to_stdout
      end
    end

    describe "#find_each_with_progress" do
      it "プログレスバーなしでfind_eachを呼び出す" do
        scope = migration.migration_targets
        results = []

        migration.send(:find_each_with_progress, scope) do |record|
          results << record
        end

        expect(results.size).to eq(3)
      end
    end

    describe "#each_with_progress" do
      it "プログレスバーなしでeachを呼び出す" do
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
