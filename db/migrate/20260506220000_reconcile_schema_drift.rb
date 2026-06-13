class ReconcileSchemaDrift < ActiveRecord::Migration[8.0]
  # Columns that production has as MEDIUMTEXT but fresh migrations create as TEXT.
  TEXT_MEDIUM = {
    announcements:         %i[body],
    contests:              %i[remark log],
    descriptions:          %i[body],
    grader_configurations: %i[description],
    messages:              %i[body],
    problems:              %i[description],
    sessions:              %i[data],
    submissions:           %i[compiler_message grader_comment],
    tags:                  %i[description],
    test_requests:         %i[compiler_message]
  }.freeze

  # Columns that production has as LONGTEXT but fresh migrations create smaller.
  TEXT_LONG = {
    submissions: %i[source],
    test_pairs:  %i[input solution]
  }.freeze

  # Tables whose timestamps are NOT NULL in production but nullable in fresh migrations.
  TIMESTAMP_NOT_NULL = %i[
    announcements contests countries descriptions grader_configurations
    grader_processes heart_beats logins messages sites submission_view_logs
    test_pairs test_requests user_contest_stats
  ].freeze

  # Join tables still on latin1 in production; missed by the earlier utf8mb3-only sweep.
  LATIN1_TABLES = %i[groups_problems groups_users problems_tags].freeze

  def up
    TEXT_MEDIUM.each do |table, cols|
      cols.each { |c| change_column table, c, :text, size: :medium }
    end

    TEXT_LONG.each do |table, cols|
      cols.each { |c| change_column table, c, :text, size: :long }
    end

    LATIN1_TABLES.each do |t|
      execute "ALTER TABLE `#{t}` CONVERT TO CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci"
    end

    change_column :user_contest_stats, :started_at, :datetime

    TIMESTAMP_NOT_NULL.each do |t|
      change_column_null t, :created_at, false
      change_column_null t, :updated_at, false
    end

    old_idx = "index_grader_processes_on_ip_and_pid"
    new_idx = "index_grader_processes_on_host_and_pid"
    if index_name_exists?(:grader_processes, old_idx)
      rename_index :grader_processes, old_idx, new_idx
    end
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
