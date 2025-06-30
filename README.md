# Dekiru::DataMigration

A Ruby on Rails library for executing data migration tasks safely and efficiently.

## Overview

`Dekiru::DataMigration` provides the following features for data migration tasks:

- **Progress Display**: Real-time progress visualization during processing
- **Transaction Management**: Automatic transaction control to ensure data safety
- **Execution Confirmation**: Confirmation prompts before committing changes
- **Side Effect Monitoring**: Tracking of database queries, job enqueuing, and email sending
- **Logging**: Detailed execution logging

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'dekiru-data_migration'
```

And then execute:

```bash
$ bundle install
```

Or install it yourself as:

```bash
$ gem install dekiru-data_migration
```

## Data Migration Operator

You can implement the necessary processing for data migration tasks with scripts like the following:

```ruby
# scripts/demo.rb
Dekiru::DataMigration::Operator.execute('Grant admin privileges to users') do
  targets = User.where("email LIKE '%sonicgarden%'")

  log "Target user count: #{targets.count}"
  find_each_with_progress(targets) do |user|
    user.update!(admin: true)
  end

  log "Updated user count: #{User.where("email LIKE '%sonicgarden%'").where(admin: true).count}"
end
```

## Data Migration Class (Recommended)

You can also define migration logic as a class, which makes testing easier:

```ruby
# scripts/20230118_demo_migration.rb
class DemoMigration < Dekiru::DataMigration::Migration
  def migration_targets
    User.where("email LIKE '%sonicgarden%'").where(admin: false)
  end

  def migrate_record(user)
    user.update!(admin: true)
  end

  def migrate
    super
    log "Updated user count: #{User.where(admin: true).count}"
  end
end

DemoMigration.run
```

### Testing Migration Classes

The class-based approach makes it easy to write unit tests:

```ruby
# spec/migrations/demo_migration_spec.rb
RSpec.describe DemoMigration do
  let(:migration) { described_class.new }

  describe '#migration_targets' do
    it 'returns correct migration targets' do
      create_list(:user, 3, email: 'test@sonicgarden.jp', admin: false)
      create_list(:user, 2, email: 'other@example.com', admin: false)

      targets = migration.migration_targets
      expect(targets.count).to eq(3)
      expect(targets.all? { |u| u.email.include?('sonicgarden') }).to be true
    end
  end

  describe '#migrate_record' do
    it 'updates user to admin' do
      user = create(:user, admin: false)
      expect { migration.migrate_record(user) }
        .to change { user.reload.admin }.from(false).to(true)
    end
  end
end
```

Execution result:
```
$ bin/rails r scripts/demo.rb
Start: Grant admin privileges to users at 2019-05-24 18:29:57 +0900

Target user count: 30
Time: 00:00:00 |=================>>| 100% Progress
Updated user count: 30

Are you sure to commit? (yes/no) > yes

Finished successfully: Grant admin privileges to users
Total time: 6.35 sec
```

## Side Effect Monitoring

By executing with the `warning_side_effects: true` option, side effects that occur during data migration tasks (database writes, job enqueuing, email sending, etc.) will be displayed.

```ruby
Dekiru::DataMigration::Operator.execute('Grant admin privileges to users', warning_side_effects: true) do
  # Processing content...
end
```

Execution result:
```
$ bin/rails r scripts/demo.rb
Start: Grant admin privileges to users at 2019-05-24 18:29:57 +0900

Target user count: 30
Time: 00:00:00 |=================>>| 100% Progress
Updated user count: 30

Write Queries!!
30 call: Update "users" SET ...

Enqueued Jobs!!
10 call: NotifyJob

Delivered Mailers!!
10 call: UserMailer

Are you sure to commit? (yes/no) > yes
```

## Generating Maintenance Scripts

You can generate maintenance scripts that use `Dekiru::DataMigration::Migration` with the generator. The filename will be prefixed with the execution date.

```bash
$ bin/rails g maintenance_script demo_migration
```

Generated file example:
```ruby
# scripts/20230118_demo_migration.rb
# frozen_string_literal: true

class DemoMigration < Dekiru::DataMigration::Migration
  def migration_targets
    # 移行対象を返すActiveRecord::Relationを定義
    # 例: User.where(some_condition: true)
    raise NotImplementedError, 'migration_targets method must be implemented'
  end

  def migrate_record(record)
    # 個別レコードの更新処理を定義
    # 例: record.update!(some_attribute: new_value)
    raise NotImplementedError, 'migrate_record method must be implemented'
  end
end

DemoMigration.run
```

### Legacy Block-based Approach

For backward compatibility, you can still use the block-based approach:

```ruby
# scripts/legacy_demo.rb
Dekiru::DataMigration::Operator.execute('demo_migration') do
  # write here
end
```

### Output Directory Configuration

The output directory for files is by default the `scripts` directory directly under the application root. You can change the output directory through configuration.

```ruby
# config/initializers/dekiru.rb
Dekiru::DataMigration.configure do |config|
  config.maintenance_script_directory = 'scripts/maintenance'
end
```

## Custom Transaction Management

For scripts using `Dekiru::DataMigration::Operator`, there are cases where the default `ActiveRecord::Base.transaction` transaction handling is insufficient, such as when writing to multiple databases is required.

You can modify the transaction handling behavior of `Dekiru::DataMigration::Operator` by customizing `Dekiru::DataMigration::TransactionProvider`.

### Implementation Example

Here's an example configuration for applications using multiple databases.

#### Application-side Configuration

```ruby
# app/models/legacy_record.rb
class LegacyRecord < ApplicationRecord
  connects_to database: { writing: :legacy, reading: :legacy }
end

# app/models/application_record.rb
class ApplicationRecord < ActiveRecord::Base
  connects_to database: { writing: :primary, reading: :primary }

  def self.with_legacy_transaction
    ActiveRecord::Base.transaction do
      LegacyRecord.transaction do
        yield
      end
    end
  end
end
```

#### Custom TransactionProvider Configuration

To configure `Dekiru::DataMigration::Operator` to also use `ApplicationRecord.with_legacy_transaction` for transaction handling, set up the following configuration:

```ruby
# config/initializers/dekiru.rb
class MyTransactionProvider < Dekiru::DataMigration::TransactionProvider
  def within_transaction(&)
    ApplicationRecord.with_legacy_transaction(&)
  end
end

Dekiru::DataMigration.configure do |config|
  config.transaction_provider = MyTransactionProvider.new
end
```

## Available Configuration Options

### Basic Configuration

```ruby
# config/initializers/dekiru.rb
Dekiru::DataMigration.configure do |config|
  # Output directory for maintenance scripts (default: "scripts")
  config.maintenance_script_directory = 'scripts/maintenance'

  # Custom transaction provider (default: Dekiru::DataMigration::TransactionProvider.new)
  config.transaction_provider = MyTransactionProvider.new
end
```

### Runtime Options

```ruby
Dekiru::DataMigration::Operator.execute('Title', options) do
  # Processing content
end
```

Available options:
- `warning_side_effects`: Display side effects (default: true)
- `without_transaction`: Don't use transactions (default: false)
- `logger`: Custom logger (default: auto-generated)
- `output`: Output destination (default: $stdout)

## Key Methods

### `log(message)`
Outputs log messages. Properly handled even during progress bar display.

### `find_each_with_progress(scope, options = {}, &block)`
Executes `find_each` with a progress bar for ActiveRecord scopes.

### `each_with_progress(enum, options = {}, &block)`
Executes processing with a progress bar for any Enumerable objects.
