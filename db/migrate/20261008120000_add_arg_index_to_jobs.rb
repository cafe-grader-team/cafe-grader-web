class AddArgIndexToJobs < ActiveRecord::Migration[8.0]
  # jobs.arg is the submission id. Job.supersede! (every rejudge, once per
  # submission in a dataset rejudge) and Job.chain_current? (after every
  # claim and before every write a judge job makes) look jobs up by it; with
  # no index each lookup scans the table, which held 249k rows on cp-grader
  # (2026-10-07 copy). Online DDL: 0.44 s on that copy.
  def change
    add_index :jobs, :arg
  end
end
