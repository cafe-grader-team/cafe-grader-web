class AddUpdatedAtToSubmissions < ActiveRecord::Migration[8.0]
  # `submissions` predates Rails' created_at/updated_at convention (unlike
  # viva_turns, viva_grades, users) — every status transition on a
  # submission (evaluating -> done/grader_error, add_judge_job, etc.)
  # already goes through ordinary ActiveRecord #update/#update! calls, so
  # once this column exists ActiveRecord::Timestamp populates it for free
  # on every save; no application code changes needed beyond this migration.
  #
  # Added so Submission.fail_stale_viva_evaluating! (app/models/submission.rb)
  # has a "how long has this been sitting in :evaluating" signal — the viva
  # grading counterpart of VivaTurn.fail_stale!, which already relies on
  # viva_turns.updated_at for the same kind of check.
  #
  # Nullable, no backfill: existing rows read NULL, and `updated_at < ?`
  # is never true against NULL in MySQL, so pre-migration rows are simply
  # invisible to the sweep instead of being falsely swept.
  def change
    add_column :submissions, :updated_at, :datetime, precision: nil
  end
end
