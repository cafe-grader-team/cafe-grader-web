# Grade history (design docs/superpowers/specs/2026-09-23-viva-grade-history-design.md):
# a failed run is never the current grade. Before the history migration a
# failed grading left the submission's only row current with no points (the
# old one-row-per-submission write path saved the raw response first). Those
# legacy rows would count as "current" and block the stuck sweeper; file them
# as history labelled 'error', stamped with the time the run happened.
class RetireFailedCurrentVivaGrades < ActiveRecord::Migration[8.0]
  def up
    execute <<~SQL
      UPDATE viva_grades
         SET superseded_at = COALESCE(graded_at, updated_at), superseded_reason = 'error'
       WHERE superseded_at IS NULL AND total_points IS NULL
    SQL
  end

  def down
    # No-op: which rows were legacy failures is not recorded, and a failed
    # run being non-current is correct under either schema.
  end
end
