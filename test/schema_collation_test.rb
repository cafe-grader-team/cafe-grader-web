require "test_helper"

# Mixed collations make cross-table string comparisons illegal in MySQL
# ("Illegal mix of collations") and were re-fixed at least four times before
# this invariant existed — each round converted the tables failing that day
# while new tables kept being born under a different default. The canonical
# collation for the primary database is utf8mb4_0900_ai_ci (MySQL 8's
# default; MariaDB unsupported). Full rationale: doc/decisions.md.
#
# If this test fails, a table or column drifted — typically a new table from
# a migration run against a database whose default differs, or a restored
# dump carrying old collations.
class SchemaCollationTest < ActiveSupport::TestCase
  CANONICAL = "utf8mb4_0900_ai_ci"

  test "every table uses the canonical collation" do
    rows = ActiveRecord::Base.connection.select_rows(<<~SQL)
      SELECT TABLE_NAME, TABLE_COLLATION
      FROM INFORMATION_SCHEMA.TABLES
      WHERE TABLE_SCHEMA = DATABASE()
        AND TABLE_TYPE = 'BASE TABLE'
        AND TABLE_COLLATION <> '#{CANONICAL}'
    SQL

    assert_empty rows,
      "Tables not using #{CANONICAL}: #{rows.map { |t, c| "#{t} (#{c})" }.join(', ')}. " \
      "Fix each with: ALTER TABLE `<table>` CONVERT TO CHARACTER SET utf8mb4 COLLATE #{CANONICAL} " \
      "(see doc/decisions.md)"
  end

  test "every string column uses the canonical collation" do
    rows = ActiveRecord::Base.connection.select_rows(<<~SQL)
      SELECT TABLE_NAME, COLUMN_NAME, COLLATION_NAME
      FROM INFORMATION_SCHEMA.COLUMNS
      WHERE TABLE_SCHEMA = DATABASE()
        AND COLLATION_NAME IS NOT NULL
        AND COLLATION_NAME <> '#{CANONICAL}'
    SQL

    assert_empty rows,
      "Columns not using #{CANONICAL}: #{rows.map { |t, col, c| "#{t}.#{col} (#{c})" }.join(', ')}. " \
      "A column-level collation override survives table conversion — fix with MODIFY COLUMN " \
      "(see doc/decisions.md)"
  end
end
