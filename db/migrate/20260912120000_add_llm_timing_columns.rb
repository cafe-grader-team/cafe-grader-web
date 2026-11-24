class AddLlmTimingColumns < ActiveRecord::Migration[8.0]
  # Splits the single wait we can measure today (row created -> row updated)
  # into its two parts, from this point forward:
  #   llm_started_at  — set just before the HTTP call to the provider, so
  #                     (started_at - created_at) is time the request spent
  #                     QUEUED in Solid Queue (viva turns / comments only;
  #                     a viva_grade row is created AFTER the call, so its
  #                     started_at has no queued span to measure against).
  #   llm_latency_ms  — the measured provider round-trip (monotonic).
  # Both nil on rows written before this migration and on error rows.
  def change
    add_column :viva_turns,  :llm_started_at, :datetime
    add_column :viva_turns,  :llm_latency_ms, :integer
    add_column :comments,    :llm_started_at, :datetime
    add_column :comments,    :llm_latency_ms, :integer
    add_column :viva_grades, :llm_started_at, :datetime
    add_column :viva_grades, :llm_latency_ms, :integer
  end
end
