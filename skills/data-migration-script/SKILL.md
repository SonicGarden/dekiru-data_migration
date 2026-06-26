---
name: data-migration-script
description: Creates data migration and deletion scripts using the dekiru-data_migration gem. Use when asked to "create a data migration script", "create a script to delete unnecessary records", or "turn this into a script", and for script-based DB operations such as deleting orphaned records after feature removal and bulk data updates.
license: MIT
---

# Data Migration Script Creation

Create data migration and deletion scripts using the `dekiru-data_migration` gem.

## Preliminary Research

Before writing a script, confirm the following:

1. **Understand the changes**: Review related Issues and PRs to understand what was deleted or changed
2. **Identify target records**: Check the schema (`db/schema.rb`) and current model code to identify the conditions for records that need to be deleted or updated

## Script Creation Steps

### 1. Generate a file with the generator

```bash
bin/rails generate maintenance_script <PascalCaseName>
```

- `<PascalCaseName>` is the name describing the operation in PascalCase (e.g., `DeleteOrphanedImages`)
- Generated file: `scripts/YYYYMMDD_<snake_case_name>.rb`
- Today's date (8 digits) is automatically appended to the class name

### 2. Edit the generated file

Implement `migration_targets` and `migrate_record` (or `migrate_batch` instead, for bulk-processing a large number of records) in the generated file.

### Common Operation Patterns

**Deleting ActiveStorage attachments**:
```ruby
def migration_targets
  ActiveStorage::Attachment.where(record_type: 'ModelName', name: 'attachment_name')
end

def migrate_record(record)
  record.purge  # synchronously delete attachment and blob
end
```

**Updating record attributes**:
```ruby
def migrate_record(record)
  record.update!(attribute: new_value)
end
```

**Deleting records**:
```ruby
def migrate_record(record)
  record.destroy!
end
```

**Conditional skip**:
```ruby
def migrate_record(record)
  return if record.some_condition?
  record.update!(...)
end
```

**Bulk update/delete a large number of records (batch processing)**:

Implement `migrate_batch` instead of `migrate_record` to receive each batch as an `ActiveRecord::Relation` via `in_batches`, allowing you to run `update_all` / `delete_all` in a single query. Use this to process a large number of records efficiently.
```ruby
def migration_targets
  User.where(active: true).where("last_login_at < ?", 1.year.ago)
end

def migrate_batch(relation)
  relation.update_all(active: false)  # one query per batch
end
```

## Execution and Verification Commands

```bash
# Check target record count (before execution)
bin/rails runner "p TargetModel.where(...).count"

# Run the script
bin/rails runner scripts/YYYYMMDD_description.rb

# Verify after execution
bin/rails runner "p TargetModel.where(...).count"
```

## Notes

- `purge` deletes synchronously (immediately removes from storage). Use `purge_later` for async deletion
- `migration_targets` must return an ActiveRecord relation (processed in batches via `find_each`)
- `migrate_batch`'s `update_all` / `delete_all` issue SQL directly without running callbacks or validations. `updated_at` is not auto-updated either, so include it explicitly if needed
- Always verify the target record count before running in production
