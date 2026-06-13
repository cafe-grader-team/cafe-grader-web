class SetDatabaseDefaultUtf8mb4AndConvertDriftedTables < ActiveRecord::Migration[8.0]
  def up
    db_name = ActiveRecord::Base.connection.current_database
    execute "ALTER DATABASE `#{db_name}` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci"

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
    raise ActiveRecord::IrreversibleMigration
  end
end
