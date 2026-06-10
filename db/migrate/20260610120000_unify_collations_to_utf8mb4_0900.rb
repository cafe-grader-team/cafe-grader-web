# All tables must share one collation: mixed collations make cross-table
# string comparisons illegal in MySQL (e.g. cheat_report joining
# logins.ip_address against submissions.ip_address). The canonical collation
# is utf8mb4_0900_ai_ci — MySQL 8's default, so future tables are born
# conforming. Decision + MariaDB consequences: doc/decisions.md. Invariant
# enforced by test/schema_collation_test.rb.
#
# Deploy note: ALTER ... CONVERT copies each table. The biggest converted
# tables (submission_view_logs, tasks, logins) take the longest — run during
# a quiet window.
class UnifyCollationsToUtf8mb40900 < ActiveRecord::Migration[8.0]
  CANONICAL = "utf8mb4_0900_ai_ci"

  def up
    # pin the database default so tables created without an explicit COLLATE
    # (and connections without one configured) conform
    execute "ALTER DATABASE `#{connection.current_database}` CHARACTER SET utf8mb4 COLLATE #{CANONICAL}"

    tables = connection.select_values(<<~SQL)
      SELECT TABLE_NAME
      FROM INFORMATION_SCHEMA.TABLES
      WHERE TABLE_SCHEMA = DATABASE()
        AND TABLE_TYPE = 'BASE TABLE'
        AND TABLE_COLLATION <> '#{CANONICAL}'
    SQL

    tables.each do |table|
      say_with_time "converting #{table}" do
        execute "ALTER TABLE `#{table}` CONVERT TO CHARACTER SET utf8mb4 COLLATE #{CANONICAL}"
      end
    end
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
