# Viva grade history (design docs/superpowers/specs/2026-09-23-viva-grade-history-design.md):
# one viva_grades row per grader run instead of one per submission. The row
# with superseded_at IS NULL is the submission's current grade; every other
# row is history. Existing rows need no backfill — each is its submission's
# only row, so it stays current; rubric_version stays NULL (= stale).
class AddHistoryToVivaGrades < ActiveRecord::Migration[8.0]
  def change
    change_table :viva_grades, bulk: true do |t|
      t.datetime :superseded_at
      t.string   :superseded_reason
      t.integer  :superseded_by_id
      t.integer  :requested_by_id
      t.string   :batch_id
      t.text     :error
    end
    # Add the composite index before dropping the old single-column one: MySQL
    # refuses to drop an index that is the sole support for a foreign key
    # (viva_grades.submission_id -> submissions), and the new composite index
    # (submission_id leads it) can take over that role without a gap.
    add_index    :viva_grades, [:submission_id, :superseded_at]
    # Rollback re-creates the unique single-column index, so it only works
    # while each submission still has at most one viva_grades row (i.e.
    # before any re-run has written history).
    remove_index :viva_grades, :submission_id, unique: true, name: 'index_viva_grades_on_submission_id'
    add_index    :viva_grades, :batch_id
  end
end
