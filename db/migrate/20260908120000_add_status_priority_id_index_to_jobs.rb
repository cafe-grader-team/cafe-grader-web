class AddStatusPriorityIdIndexToJobs < ActiveRecord::Migration[8.0]
  # The judge polls `jobs` on `status` (Job.has_waiting_job, 5 Hz per grader
  # when idle, faster when busy) and claims with
  #   WHERE status = wait ORDER BY priority DESC, id ASC LIMIT 1 FOR UPDATE SKIP LOCKED
  # (Job.take_oldest_waiting_job); Job.reclaim_orphaned! filters on
  # status = process. The table had no index on status, so every poll was a
  # full scan and — under REPEATABLE READ — every claim locked every row it
  # scanned, which made SKIP LOCKED hand a concurrent grader nothing: measured
  # 2026-09-08 on a 33k-row copy, 353 of 1,200 claims came back empty without
  # this index and 0 with it; the idle poll went from 2.3 ms to 0.15 ms and
  # the claim from 13.9 ms to 2.7 ms, while insert/update cost was unchanged
  # (each is dominated by the commit's log flush). The leading column serves
  # the poll and the reclaim sweep; the full key serves the claim in its sort
  # order with no filesort. Online DDL: 100 ms at 33k rows, 443 ms at 200k.
  def change
    add_index :jobs, [:status, :priority, :id], order: { priority: :desc },
              name: 'index_jobs_on_status_priority_id'
  end
end
