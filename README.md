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

## Data Migration Class

Define migration logic as a class:

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

### Batch Processing with `migrate_batch`

When you need to update or delete a large number of records efficiently, you can define `migrate_batch` instead of `migrate_record`. It processes records in batches using ActiveRecord's `in_batches`, yielding each batch as an `ActiveRecord::Relation` so you can run a single `update_all` / `delete_all` query per batch. The progress bar advances per batch rather than per record.

`migrate_batch` and `migrate_record` are mutually exclusive — if you implement `migrate_batch`, the batch path is used automatically.

```ruby
# scripts/20230118_deactivate_stale_users.rb
class DeactivateStaleUsersMigration < Dekiru::DataMigration::Migration
  def migration_targets
    User.where(active: true).where("last_login_at < ?", 1.year.ago)
  end

  def migrate_batch(relation)
    relation.update_all(active: false)
  end
end

DeactivateStaleUsersMigration.run
```

#### Specifying the batch size

Pass `batch_size` to `run` to control how many records are fetched per batch. It applies to both paths — `in_batches(of:)` for `migrate_batch` and `find_each(batch_size:)` for `migrate_record`. When omitted, ActiveRecord's default of 1000 is used.

```ruby
DeactivateStaleUsersMigration.run(batch_size: 500)
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

By passing `warning_side_effects: true` to `run`, side effects that occur during data migration tasks (database writes, job enqueuing, email sending, etc.) will be displayed.

```ruby
DemoMigration.run(warning_side_effects: true)
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
    # Return an ActiveRecord::Relation of records to migrate
    # e.g. User.where(some_condition: true)
    raise NotImplementedError, 'migration_targets method must be implemented'
  end

  def migrate_record(record)
    # Define the update logic for each record
    # e.g. record.update!(some_attribute: new_value)
    raise NotImplementedError, 'migrate_record method must be implemented'
  end
end

DemoMigration.run
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

Pass options to `Migration.run`:

```ruby
DemoMigration.run(warning_side_effects: true, without_transaction: false)
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
Executes `find_each` with a progress bar for ActiveRecord scopes. Pass `batch_size:` in `options` to control how many records are fetched per batch (forwarded to `find_each(batch_size:)`).

### `each_with_progress(enum, options = {}, &block)`
Executes processing with a progress bar for any Enumerable objects.

## Agent Skills

This repository provides an agent skill for creating data migration scripts.

### Available Skills

#### `data-migration-script`

Automatically creates data migration and deletion scripts using the `dekiru-data_migration` gem.

**Triggers**: The agent will use this skill when you ask to "create a data migration script", "create a script to delete unnecessary records", or similar requests involving DB operations via scripts (bulk updates, deleting orphaned records, deleting ActiveStorage files, etc.).

**Install**:

```bash
gh skill install SonicGarden/dekiru-data_migration
```
