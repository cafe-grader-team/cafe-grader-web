class ConvertUtf8mb3TablesToUtf8mb4 < ActiveRecord::Migration[8.0]
  def up
    tables = connection.select_values(<<~SQL)
      SELECT TABLE_NAME
      FROM INFORMATION_SCHEMA.TABLES
      WHERE TABLE_SCHEMA = DATABASE()
        AND TABLE_COLLATION LIKE 'utf8mb3%'
    SQL

    tables.each do |table|
      execute "ALTER TABLE `#{table}` CONVERT TO CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci"
    end
  end

  def down
    # No-op: converting back to utf8mb3 could cause data loss
    raise ActiveRecord::IrreversibleMigration
  end
end
