class AddUniqueSubmissionTestcaseIndexToEvaluations < ActiveRecord::Migration[8.0]
  # One evaluation per (submission, testcase). Nothing enforced it: two job
  # chains of one submission (a rejudge while the first still ran) could each
  # create the row, and Scorer#process then saw a doubled testcase list and
  # failed with "Evaluations are missing". Evaluator now finds or creates the
  # row against this index.
  #
  # Before the index: delete rows whose submission is gone (4,279 on the
  # cp-grader copy of 2026-10-07, all with submission_id NULL) and keep only
  # the newest row of any duplicated pair (312 pairs there, all among those
  # orphans; none on a live submission). The ids come from plain SELECTs,
  # which take no row locks, and are deleted by primary key in batches, so
  # judge writes to evaluations never wait behind a full-table scan.
  #
  # On that copy (7.56 M rows) the migration took 30 s: orphan scan 3 s,
  # duplicate scan 15 s, index build 11 s. The build is online
  # (ALGORITHM=INPLACE, LOCK=NONE): on a scratch copy of the table a second
  # connection inserted 48 rows during it, slowest 25 ms. The unique
  # index leads with submission_id, so it replaces
  # index_evaluations_on_submission_id. If a judge still on the old version
  # creates a duplicate between the cleanup and the build, the ALTER stops on
  # it; run the migration again.
  BATCH = 1000

  def up
    delete_evaluations(select_values(<<~SQL))
      SELECT e.id FROM evaluations e
      LEFT JOIN submissions s ON s.id = e.submission_id
      WHERE s.id IS NULL
    SQL
    delete_evaluations(select_values(<<~SQL))
      SELECT e.id FROM evaluations e
      JOIN (SELECT submission_id, testcase_id, MAX(id) AS keep_id
            FROM evaluations
            WHERE testcase_id IS NOT NULL
            GROUP BY submission_id, testcase_id
            HAVING COUNT(*) > 1) d
        ON d.submission_id = e.submission_id AND d.testcase_id = e.testcase_id AND e.id < d.keep_id
    SQL
    execute <<~SQL
      ALTER TABLE evaluations
        ADD UNIQUE INDEX index_evaluations_on_submission_id_and_testcase_id (submission_id, testcase_id),
        DROP INDEX index_evaluations_on_submission_id,
        ALGORITHM=INPLACE, LOCK=NONE
    SQL
  end

  # Restores the old index only; the deleted rows are gone.
  def down
    execute <<~SQL
      ALTER TABLE evaluations
        ADD INDEX index_evaluations_on_submission_id (submission_id),
        DROP INDEX index_evaluations_on_submission_id_and_testcase_id,
        ALGORITHM=INPLACE, LOCK=NONE
    SQL
  end

  private

  # connection.exec_delete, not execute: the migration log would print every id
  def delete_evaluations(ids)
    say_with_time "deleting #{ids.size} evaluation rows" do
      ids.each_slice(BATCH) { |batch| connection.exec_delete("DELETE FROM evaluations WHERE id IN (#{batch.join(',')})") }
      ids.size
    end
  end
end
