require_relative "data_migration/operator"

module Dekiru
  # 後方互換性のためのエイリアス
  # 新しいコードでは Dekiru::DataMigration::Operator を使用してください
  DataMigrationOperator = DataMigration::Operator
end
